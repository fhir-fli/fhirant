// How often does validation find something in what our own apps write,
// and what does it cost per resource?
//
// Grey 2026-11-01: "if its coming from one of our apps ... isn't it almost
// automatically going to be valid?" Unmeasured. This validates every
// resource of a corpus our code generated against its base type and against
// every profile it claims in meta.profile (the engine itself reads no
// meta.profile: fhir_validation 0.13.0 validateFhirMap takes one
// StructureDefinition, defaulting to the base type), and times each.
//
// The store is filled the way the server fills it: the packaged
// specification through loadSpecResources, then the guide's conformance
// resources (StructureDefinition, ValueSet, CodeSystem) saved as uploads.
//
// Usage, from packages/fhirant_server:
//   dart run tool/validation_measure/measure_corpus.dart \
//     <spec dir> <guide output dir> <corpus bundle> <out dir>
//
// Writes, one line per resource, flushed as it goes:
//   <out>/resources.tsv  index, type, id, against, ms, errors, warnings
//   <out>/issues.tsv     index, type, id, against, severity, location, text
//   <out>/crashes.tsv    validations that threw, and the element that does it
// and <out>/summary.txt at the end.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_validation/fhir_r4_validation.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/db_resource_cache.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart';

const _guideTypes = ['StructureDefinition', 'ValueSet', 'CodeSystem'];

Future<void> main(List<String> args) async {
  if (args.length < 4 || args.length > 6) {
    stderr.writeln(
      'usage: measure_corpus.dart <spec> <guide> <bundle> <out> '
      '[<limit>] [db|memory]',
    );
    exit(64);
  }
  final [specDir, guideDir, bundlePath, outDir, ...rest] = args;
  // An optional cap on resources, and which cache serves the engine: `db`
  // (fhirant's DbResourceCache, the default) or `memory` (fhir_path's
  // CanonicalResourceCache filled with the same resources), to tell a fault
  // in our cache from one in the engine.
  final limit = rest.isNotEmpty ? int.parse(rest[0]) : null;
  final cacheMode = rest.length > 1 ? rest[1] : 'db';
  Directory(outDir).createSync(recursive: true);
  final resourcesOut = File('$outDir/resources.tsv').openSync(
    mode: FileMode.write,
  )..writeStringSync('index\ttype\tid\tagainst\tms\terrors\twarnings\n');
  final issuesOut = File('$outDir/issues.tsv').openSync(mode: FileMode.write)
    ..writeStringSync(
      'index\ttype\tid\tagainst\tseverity\tlocation\tdiagnostics\n',
    );
  final crashesOut = File('$outDir/crashes.tsv').openSync(
    mode: FileMode.write,
  )..writeStringSync('index\ttype\tid\tagainst\tculprits\texception\n');
  final log = File('$outDir/progress.log').openSync(mode: FileMode.write);
  void note(String line) {
    log
      ..writeStringSync('${DateTime.now().toIso8601String()} $line\n')
      ..flushSync();
  }

  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();

  final specClock = Stopwatch()..start();
  await loadSpecResources(db, specDir);
  note('spec loaded in ${specClock.elapsedMilliseconds} ms: '
      '${await db.getResourceCount(fhir.R4ResourceType.StructureDefinition)} '
      'StructureDefinitions, '
      '${await db.getResourceCount(fhir.R4ResourceType.ValueSet)} ValueSets, '
      '${await db.getResourceCount(fhir.R4ResourceType.CodeSystem)} '
      'CodeSystems');

  var guideLoaded = 0;
  for (final file in Directory(guideDir).listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    // The publisher writes each resource once as <Type>-<id>.json; its
    // .xml/.ttl renderings and <Type>-<id>.<format>.json views are skipped.
    if (!name.endsWith('.json') || '.'.allMatches(name).length != 1) continue;
    if (!_guideTypes.any((t) => name.startsWith('$t-'))) continue;
    await db.saveResource(
      fhir.Resource.fromJsonString(file.readAsStringSync()),
    );
    guideLoaded++;
  }
  note('guide resources loaded: $guideLoaded');

  final bundle =
      jsonDecode(File(bundlePath).readAsStringSync()) as Map<String, dynamic>;
  final entries = (bundle['entry'] as List).cast<Map<String, dynamic>>();
  note('corpus: ${entries.length} resources');

  const validator = FhirValidationEngine();
  final dbCache = DbResourceCache(db);
  final ResourceCache cache;
  if (cacheMode == 'memory') {
    final memory = CanonicalResourceCache();
    for (final type in [
      fhir.R4ResourceType.StructureDefinition,
      fhir.R4ResourceType.ValueSet,
      fhir.R4ResourceType.CodeSystem,
    ]) {
      for (final r in await db.getResourcesByType(type)) {
        await memory.saveCanonicalResource(r);
      }
    }
    cache = memory;
  } else {
    cache = dbCache;
  }
  note('cache: $cacheMode');
  var errorResources = 0;
  var crashedResources = 0;
  var errorIssues = 0;
  var warningIssues = 0;
  final times = <int>[];
  final missingProfiles = <String>{};

  final count = limit == null ? entries.length : limit.clamp(0, entries.length);
  for (var i = 0; i < count; i++) {
    final json = entries[i]['resource'] as Map<String, dynamic>;
    final type = json['resourceType'] as String;
    final id = json['id'] as String? ?? '';
    final meta = json['meta'] as Map<String, dynamic>?;
    final claimed = [
      for (final p in (meta?['profile'] as List?) ?? const []) p as String,
    ];
    var resourceHasError = false;
    for (final against in [null, ...claimed]) {
      fhir.StructureDefinition? profile;
      if (against != null) {
        profile = await dbCache.canonical<fhir.StructureDefinition>(against);
        if (profile == null) {
          missingProfiles.add(against);
          resourcesOut.writeStringSync(
            '$i\t$type\t$id\t$against\t-\tPROFILE NOT LOADED\t-\n',
          );
          continue;
        }
      }
      final clock = Stopwatch()..start();
      final ValidationResults results;
      try {
        results = await validator.validateFhirMap(
          structureToValidate: json,
          structureDefinition: profile,
          resourceCache: cache,
        );
      } on Exception catch (e) {
        // The engine threw instead of reporting an issue: validation not
        // performed. Recorded with the top-level elements whose removal
        // alone stops the throw, which names the element that causes it.
        crashedResources++;
        final culprits = <String>[];
        for (final key in json.keys) {
          if (key == 'resourceType') continue;
          try {
            await validator.validateFhirMap(
              structureToValidate: Map.of(json)..remove(key),
              structureDefinition: profile,
              resourceCache: cache,
            );
            culprits.add(key);
          } on Exception {
            // Still throws without this element.
          }
        }
        final text = '$e'.replaceAll(RegExp(r'\s+'), ' ');
        crashesOut
          ..writeStringSync(
            '$i\t$type\t$id\t${against ?? 'base'}\t'
            '${culprits.join(',')}\t$text\n',
          )
          ..flushSync();
        resourcesOut
          ..writeStringSync(
            '$i\t$type\t$id\t${against ?? 'base'}\t-\tTHREW\t-\n',
          )
          ..flushSync();
        continue;
      }
      final ms = clock.elapsedMilliseconds;
      times.add(ms);
      final issues = results.toOperationOutcome().issue;
      var errors = 0;
      var warnings = 0;
      for (final issue in issues) {
        final severity = issue.severity.valueString ?? '';
        if (severity == 'error' || severity == 'fatal') errors++;
        if (severity == 'warning') warnings++;
        if (severity == 'information') continue;
        final location = [
          ...?issue.expression?.map((e) => e.valueString),
          ...?issue.location?.map((e) => e.valueString),
        ].join(',');
        final text = (issue.diagnostics?.valueString ?? '')
            .replaceAll(RegExp(r'\s+'), ' ');
        issuesOut.writeStringSync(
          '$i\t$type\t$id\t${against ?? 'base'}\t$severity\t$location\t$text\n',
        );
      }
      issuesOut.flushSync();
      errorIssues += errors;
      warningIssues += warnings;
      if (errors > 0) resourceHasError = true;
      resourcesOut
        ..writeStringSync(
          '$i\t$type\t$id\t${against ?? 'base'}\t$ms\t$errors\t$warnings\n',
        )
        ..flushSync();
    }
    if (resourceHasError) errorResources++;
    if (i % 100 == 0) note('validated ${i + 1}/${entries.length}');
  }

  times.sort();
  int pct(double p) => times[((times.length - 1) * p).round()];
  final summary = StringBuffer()
    ..writeln('corpus: $bundlePath')
    ..writeln('resources: ${entries.length}')
    ..writeln('validations run: ${times.length}')
    ..writeln('resources with >=1 error: $errorResources')
    ..writeln('validations that threw: $crashedResources')
    ..writeln('error issues: $errorIssues')
    ..writeln('warning issues: $warningIssues')
    ..writeln('claimed profiles not loaded: ${missingProfiles.length} '
        '${missingProfiles.join(' ')}')
    ..writeln('ms per validation: median ${pct(0.5)}, p90 ${pct(0.9)}, '
        'p99 ${pct(0.99)}, max ${times.last}, '
        'total ${times.fold<int>(0, (a, b) => a + b)}');
  File('$outDir/summary.txt').writeAsStringSync(summary.toString());
  note('done');
  resourcesOut.closeSync();
  crashesOut.closeSync();
  issuesOut.closeSync();
  log.closeSync();
  await db.close();
}
