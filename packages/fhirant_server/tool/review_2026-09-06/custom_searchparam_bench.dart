// What indexing through FHIRPath at write time costs against the generated
// extractor, and whether the two agree, measured on the MIMIC sample
// (the custom-SearchParameter question, fhirant-search-indexing-gap memory).
//
//   dart run tool/review_2026-09-06/custom_searchparam_bench.dart \
//     tool/review_2026-09-06/custom_searchparam_bench.tsv <label> [per_file=200]
//
// Route A is what fhir_r4_db does today: `r4Model.extract`, the generated
// Dart. Route B is what HAPI/Smile CDR and the Azure FHIR service do for
// every parameter: parse each R4 SearchParameter expression once, evaluate
// it with the fhir_path engine on every save, hand the values to the same
// row builders by parameter type. Per resource type: time of each route,
// rows produced, rows one route has and the other does not (compared as
// searchName plus value). Rows are appended and flushed per type; the
// disagreements go to <tsv>.mismatches.tsv per type, counted per parameter
// and side with one example row each.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';

/// One indexable fragment of a SearchParameter expression for one base.
class _Param {
  _Param(this.code, this.type, this.fragment, this.node);
  final String code;
  final String type;
  final String fragment;
  final ExpressionNode node;
}

List<String> _splitUnion(String expression) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < expression.length; i++) {
    final c = expression[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == '|' && depth == 0) {
      parts.add(expression.substring(start, i).trim());
      start = i + 1;
    }
  }
  parts.add(expression.substring(start).trim());
  return parts;
}

String _head(String fragment) =>
    fragment.replaceFirst(RegExp(r'^\(+'), '').split('.').first;

Future<void> main(List<String> args) async {
  final tsv = File(args[0]);
  final label = args[1];
  final perFile = args.length > 2 ? int.parse(args[2]) : 200;
  final mismatches = File('${tsv.path}.mismatches.tsv');
  if (!tsv.existsSync()) {
    tsv.writeAsStringSync(
      'label\tresource_type\tresources\texpressions\tparse_ms'
      '\tgen_ms\tgen_us_per_resource\tfp_ms\tfp_us_per_resource'
      '\trows_gen\trows_fp\tonly_gen\tonly_fp\tfp_errors\n',
    );
  }
  if (!mismatches.existsSync()) {
    mismatches.writeAsStringSync(
      'label\tresource_type\tsearch_name\tside\tcount\texample_id'
      '\texample_row\n',
    );
  }

  final engine = await FHIRPathEngine.create(WorkerContext());
  final indexer = r4Model.indexer;

  // Every R4 SearchParameter fragment, grouped by the base it is written on.
  final byBase = <String, List<_Param>>{};
  var parseErrors = 0;
  final parseSw = Stopwatch()..start();
  for (final line
      in File('assets/fhir_spec/search-parameters.ndjson').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final sp = jsonDecode(line) as Map<String, dynamic>;
    final expression = sp['expression'] as String?;
    if (expression == null) continue;
    final type = sp['type'] as String;
    if (type == 'composite') continue;
    for (final fragment in _splitUnion(expression)) {
      final head = _head(fragment);
      if (head == 'Resource' || head == 'DomainResource') continue;
      try {
        byBase.putIfAbsent(head, () => []).add(
              _Param(
                sp['code'] as String,
                type,
                fragment,
                engine.parse(fragment),
              ),
            );
      } catch (e) {
        parseErrors++;
        stdout.writeln('parse failed: $fragment: $e');
      }
    }
  }
  parseSw.stop();
  stdout.writeln(
    'parsed ${byBase.values.fold<int>(0, (n, l) => n + l.length)} fragments '
    'for ${byBase.length} bases in ${parseSw.elapsedMilliseconds} ms, '
    '$parseErrors parse errors',
  );

  Set<String> keys(SearchParameterLists l) => {
        for (final r in l.stringParams)
          'string|${r.searchName.value}|${r.stringValue.value}',
        for (final r in l.tokenParams)
          [
            'token',
            r.searchName.value,
            r.tokenSystem.value,
            r.tokenValue.value,
          ].join('|'),
        for (final r in l.referenceParams)
          'reference|${r.searchName.value}|${r.referenceValue.value}',
        for (final r in l.dateParams)
          'date|${r.searchName.value}|${r.dateString.value}',
        for (final r in l.quantityParams)
          [
            'quantity',
            r.searchName.value,
            r.quantityValue.value,
            r.quantityCode.value,
          ].join('|'),
        for (final r in l.numberParams)
          'number|${r.searchName.value}|${r.numberValue.value}',
        for (final r in l.uriParams)
          'uri|${r.searchName.value}|${r.uriValue.value}',
      };

  SearchParameterLists rowsFor(
    fhir.Resource resource,
    _Param p,
    List<fhir.FhirBase> values,
    SearchParameterLists into,
  ) {
    final rt = resource.resourceTypeString;
    final id = resource.id.toString();
    var i = 0;
    for (final v in values) {
      switch (p.type) {
        case 'string':
          into.stringParams.addAll(
            indexer.stringRows(v, rt, id, 0, p.fragment, i, searchName: p.code),
          );
        case 'token':
          into.tokenParams.addAll(
            indexer.tokenRows(v, rt, id, 0, p.fragment, i, searchName: p.code),
          );
        case 'reference':
          into.referenceParams.addAll(
            indexer.referenceRows(
              v,
              rt,
              id,
              0,
              p.fragment,
              i,
              searchName: p.code,
            ),
          );
        case 'date':
          into.dateParams.addAll(
            indexer.dateRows(v, rt, id, 0, p.fragment, i, searchName: p.code),
          );
        case 'quantity':
          into.quantityParams.addAll(
            indexer.quantityRows(
              v,
              rt,
              id,
              0,
              p.fragment,
              i,
              searchName: p.code,
            ),
          );
        case 'number':
          into.numberParams.addAll(
            indexer.numberRows(v, rt, id, 0, p.fragment, i, searchName: p.code),
          );
        case 'uri':
          into.uriParams.addAll(
            indexer.uriRows(v, rt, id, 0, p.fragment, i, searchName: p.code),
          );
        case 'special':
          into.specialParams.addAll(
            indexer.specialRows(
              v,
              rt,
              id,
              0,
              p.fragment,
              i,
              searchName: p.code,
            ),
          );
      }
      i++;
    }
    return into;
  }

  final files = Directory('assets/mimic')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ndjson'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final resources = <fhir.Resource>[];
    for (final line in file.readAsLinesSync().take(perFile)) {
      if (line.trim().isEmpty) continue;
      resources.add(
        fhir.Resource.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
    }
    if (resources.isEmpty) continue;
    final rt = resources.first.resourceTypeString;
    final params = byBase[rt] ?? const <_Param>[];
    final name = file.uri.pathSegments.last.replaceAll('.ndjson', '');

    // Route A, timed alone.
    final genSw = Stopwatch()..start();
    final genLists = [for (final r in resources) r4Model.extract(r)];
    genSw.stop();

    // Route B, timed alone.
    var fpErrors = 0;
    final fpSw = Stopwatch()..start();
    final fpLists = <SearchParameterLists>[];
    for (final r in resources) {
      final into = SearchParameterLists();
      for (final p in params) {
        try {
          rowsFor(
            r,
            p,
            (await engine.evaluate(r, p.node)).cast<fhir.FhirBase>(),
            into,
          );
        } catch (e) {
          fpErrors++;
          if (fpErrors <= 5) stdout.writeln('  $rt ${p.code}: $e');
        }
      }
      fpLists.add(into);
    }
    fpSw.stop();

    var rowsGen = 0;
    var rowsFp = 0;
    var onlyGen = 0;
    var onlyFp = 0;
    // Disagreements counted per parameter and side, with one example row
    // each; per-row output was 18 MB for one run.
    final counts = <String, int>{};
    final examples = <String, String>{};
    for (var i = 0; i < resources.length; i++) {
      final a = keys(genLists[i]);
      final b = keys(fpLists[i]);
      rowsGen += a.length;
      rowsFp += b.length;
      for (final k in a.difference(b)) {
        onlyGen++;
        final key = '${k.split('|')[1]}\tgen';
        counts[key] = (counts[key] ?? 0) + 1;
        examples[key] ??= '${resources[i].id}\t$k';
      }
      for (final k in b.difference(a)) {
        onlyFp++;
        final key = '${k.split('|')[1]}\tfp';
        counts[key] = (counts[key] ?? 0) + 1;
        examples[key] ??= '${resources[i].id}\t$k';
      }
    }
    final sink = mismatches.openWrite(mode: FileMode.append);
    for (final e in counts.entries) {
      sink.writeln('$label\t$name\t${e.key}\t${e.value}\t${examples[e.key]}');
    }
    await sink.flush();
    await sink.close();

    final n = resources.length;
    final line = '$label\t$name\t$n\t${params.length}\t'
        '${parseSw.elapsedMilliseconds}\t'
        '${genSw.elapsedMilliseconds}\t'
        '${(genSw.elapsedMicroseconds / n).toStringAsFixed(0)}\t'
        '${fpSw.elapsedMilliseconds}\t'
        '${(fpSw.elapsedMicroseconds / n).toStringAsFixed(0)}\t'
        '$rowsGen\t$rowsFp\t$onlyGen\t$onlyFp\t$fpErrors\n';
    tsv.writeAsStringSync(line, mode: FileMode.append, flush: true);
    stdout.write(line);

    // For scale: the whole save (extract + SQLite rows + history) of the same
    // resources into a fresh in-memory store, reported in the gen columns.
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final saveSw = Stopwatch()..start();
    for (var start = 0; start < resources.length; start += 500) {
      await db.saveResources(
        resources.sublist(
          start,
          start + 500 > resources.length ? resources.length : start + 500,
        ),
      );
    }
    saveSw.stop();
    await db.close();
    final saveLine = '$label\tsave:$name\t$n\t${params.length}\t0\t'
        '${saveSw.elapsedMilliseconds}\t'
        '${(saveSw.elapsedMicroseconds / n).toStringAsFixed(0)}\t'
        '0\t0\t0\t0\t0\t0\t0\n';
    tsv.writeAsStringSync(saveLine, mode: FileMode.append, flush: true);
    stdout.write(saveLine);
  }
}
