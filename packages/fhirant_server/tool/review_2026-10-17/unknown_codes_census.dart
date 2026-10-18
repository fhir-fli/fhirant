// Runs unknownRequiredCodes over every published R4B example, which are
// valid, so every row it writes is a false refusal the write path would
// make. One line per flagged example to unknown_codes_census.tsv, then a
// count line. Known positive first: Observation.status "not-a-status".
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/unknown_codes_census.dart <examples-json dir>
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/unknown_codes.dart';

void main(List<String> args) {
  final out = File('tool/review_2026-10-17/unknown_codes_census.tsv')
    ..writeAsStringSync('file\tflags\n', flush: true);
  final positive = unknownRequiredCodes(
    fhir.Resource.fromJson({
      'resourceType': 'Observation',
      'status': 'not-a-status',
      'code': {'text': 'x'},
    }),
  );
  out.writeAsStringSync(
    'KNOWN POSITIVE\t$positive\n',
    mode: FileMode.append,
    flush: true,
  );
  var read = 0;
  var parsed = 0;
  var flagged = 0;
  final files = Directory(args.first)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    read++;
    final fhir.Resource r;
    try {
      final json = jsonDecode(f.readAsStringSync());
      if (json is! Map<String, dynamic> || json['resourceType'] == null) {
        continue;
      }
      r = fhir.Resource.fromJson(json);
    } catch (_) {
      continue;
    }
    parsed++;
    final flags = unknownRequiredCodes(r);
    if (flags.isNotEmpty) {
      flagged++;
      out.writeAsStringSync(
        '${f.uri.pathSegments.last}\t${flags.join('; ')}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }
  out.writeAsStringSync(
    'TOTAL\tfiles $read, parsed $parsed, flagged $flagged\n',
    mode: FileMode.append,
    flush: true,
  );
  stdout.writeln('files $read, parsed $parsed, flagged $flagged');
}
