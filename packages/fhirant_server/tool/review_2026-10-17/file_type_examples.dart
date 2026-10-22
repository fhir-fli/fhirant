// What fhirant's file check (fileRefusal with no scanner: the type check
// alone, as on the phone) says of every file in the published examples:
// the known positives for OWASP ASVS 5.0.0 V5.2.2.
//
// One row per file found to file_type_examples.tsv, flushed: source file,
// path, declared type, and the decision (stored, or the status and reason).
// A last row counts the files read, those that parse, and the files found.
//
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/file_type_examples.dart <dir>...
import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_server/src/utils/file_data.dart';
import 'package:fhirant_server/src/utils/file_refusal.dart';
import 'package:fhirant_server/src/utils/file_type.dart';

Future<void> main(List<String> args) async {
  final out = File('tool/review_2026-10-17/file_type_examples.tsv')
      .openSync(mode: FileMode.write)
    ..writeStringSync('source\tpath\ttype\tdecision\n');
  var read = 0;
  var parsed = 0;
  var files = 0;
  var refused = 0;
  for (final root in args) {
    final entries = Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in entries) {
      read++;
      fhir.Resource resource;
      try {
        final json = jsonDecode(f.readAsStringSync());
        if (json is! Map<String, dynamic> || json['resourceType'] is! String) {
          continue;
        }
        resource = fhir.Resource.fromJson(json);
      } catch (_) {
        continue;
      }
      parsed++;
      for (final file in fileData(resource)) {
        files++;
        // Each file on its own, so one refusal does not hide the next.
        final bytes = file.bytes;
        String decision;
        if (bytes == null) {
          decision = '400 not base64';
        } else if (file.type == null && file.typeRequired) {
          decision = '400 no type';
        } else if (!file.isFile) {
          decision = 'stored (not a file: no type check)';
        } else {
          final why = fileTypeRefusal(file.type, bytes);
          decision = why == null ? 'stored' : '422 $why';
        }
        if (!decision.startsWith('stored')) refused++;
        out
          ..writeStringSync(
            '${f.path}\t${file.path}\t${file.type ?? ''}\t$decision\n',
          )
          ..flushSync();
      }
      // The server's own helper must agree with the per-file rows.
      final whole = await fileRefusal(null, resource);
      if (whole != null) {
        out
          ..writeStringSync(
            '${f.path}\t(resource)\t\t${whole.status} ${whole.message}\n',
          )
          ..flushSync();
      }
    }
  }
  final summary = 'read $read parsed $parsed files $files refused $refused';
  out
    ..writeStringSync('summary\t\t\t$summary\n')
    ..closeSync();
  stdout.writeln(summary);
}
