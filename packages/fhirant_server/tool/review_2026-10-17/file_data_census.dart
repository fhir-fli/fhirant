// Does fileData (lib/src/utils/file_data.dart) find every file in a resource?
// Checked against every R4B example the specification publishes, by a
// second instrument that knows nothing of the model: a plain JSON walk
// that counts every key one of R4B's 18 base64Binary elements can appear
// under (`data`, `hash`, `query`, `carrierAIDC`, and any `...Base64Binary`
// choice key, read from profiles-types and profiles-resources 2026-10-21).
// The JSON walk over-counts (SampledData.data is a string, not a file), so
// every file where the two disagree is written out to be read.
//
// One row per disagreeing file, then a totals row, to file_data_census.tsv,
// flushed as it runs.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/file_data_census.dart <examples-json dir>
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/file_data.dart';

const _keys = {'data', 'hash', 'query', 'carrierAIDC'};

int _jsonCount(Object? node) {
  var n = 0;
  if (node is Map) {
    for (final MapEntry(:key, :value) in node.entries) {
      if (key is String &&
          (_keys.contains(key) || key.endsWith('Base64Binary'))) {
        n += value is List ? value.length : 1;
      }
      n += _jsonCount(value);
    }
  } else if (node is List) {
    for (final v in node) {
      n += _jsonCount(v);
    }
  }
  return n;
}

Future<void> main(List<String> args) async {
  final out = File('tool/review_2026-10-17/file_data_census.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('file\tjson_keys\tfile_data\tpaths\n')
    ..flushSync();
  final files = Directory(args.single)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  var read = 0;
  var unparsed = 0;
  var jsonTotal = 0;
  var foundTotal = 0;
  var differ = 0;
  for (final f in files) {
    final Object? json;
    final fhir.Resource resource;
    try {
      json = jsonDecode(f.readAsStringSync());
      resource = fhir.Resource.fromJson(json! as Map<String, dynamic>);
    } catch (_) {
      unparsed++;
      out
        ..writeStringSync('${f.uri.pathSegments.last}\tunparsed\t\t\n')
        ..flushSync();
      continue;
    }
    read++;
    final expected = _jsonCount(json);
    final found = fileData(resource).map((d) => d.path).toList();
    jsonTotal += expected;
    foundTotal += found.length;
    if (expected != found.length) {
      differ++;
      out
        ..writeStringSync(
          '${f.uri.pathSegments.last}\t$expected\t${found.length}\t'
          '${found.join(',')}\n',
        )
        ..flushSync();
    }
  }
  final totals = 'TOTAL files=${files.length} read=$read unparsed=$unparsed '
      'json_keys=$jsonTotal file_data=$foundTotal differ=$differ';
  out
    ..writeStringSync('$totals\n')
    ..flushSync()
    ..closeSync();
  stdout.writeln(totals);
}
