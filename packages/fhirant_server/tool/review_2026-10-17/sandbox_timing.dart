// How long does each program in program_sandbox_test run with no deadline
// pressure? The slow ones must stay far above the test deadline, the fast
// ones far below. One line per run to sandbox_timing.tsv.
// Run from packages/fhirant_server:
//   dart run tool/review_2026-10-17/sandbox_timing.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';

import '../../test/integration/test_helpers.dart';

Future<void> main() async {
  final out = File('tool/review_2026-10-17/sandbox_timing.tsv')
    ..writeAsStringSync('program\trun\tms\tstatus\n', flush: true);
  final db = FhirAntDb(NativeDatabase.memory());
  await db.initialize();
  final server = FhirAntServer(
    db,
    jwtSecret: testJwtSecret,
    programDeadline: const Duration(seconds: 120),
  );
  final handler = server.createHandler(server.createRouter());
  final token = await issueTestToken(db, role: 'admin', scopes: ['system/*.*']);
  await db.saveResource(fhir.Patient(id: 'fp'.toFhirString));

  String nested(int depth) {
    const d = '(0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9)';
    var expr = r'$this';
    for (var i = 0; i < depth; i++) {
      expr = '$d.select($expr)';
    }
    return '$expr.count()';
  }

  Map<String, dynamic> map(String expression) => {
        'resourceType': 'StructureMap',
        'url': 'http://example.org/StructureMap/slow',
        'name': 'Slow',
        'status': 'draft',
        'structure': [
          {
            'url': 'http://hl7.org/fhir/StructureDefinition/Patient',
            'mode': 'source',
            'alias': 'src',
          },
          {
            'url': 'http://hl7.org/fhir/StructureDefinition/Patient',
            'mode': 'target',
            'alias': 'tgt',
          },
        ],
        'group': [
          {
            'name': 'main',
            'typeMode': 'none',
            'input': [
              {'name': 'source', 'type': 'src', 'mode': 'source'},
              {'name': 'target', 'type': 'tgt', 'mode': 'target'},
            ],
            'rule': [
              {
                'name': 'id',
                'source': [
                  {'context': 'source'},
                ],
                'target': [
                  {
                    'context': 'target',
                    'contextType': 'variable',
                    'element': 'id',
                    'transform': 'evaluate',
                    'parameter': [
                      {'valueString': expression},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      };

  final programs = <(String, int, Future<dynamic> Function())>[
    (
      'fhirpath-nested3',
      5,
      () async => handler(
            testRequest(
              'GET',
              r'/$fhirpath?resourceType=Patient&resourceId=fp&expression='
                  '${Uri.encodeQueryComponent(nested(3))}',
              authToken: token,
            ),
          )
    ),
    (
      'fhirpath-nested7',
      1,
      () async => handler(
            testRequest(
              'GET',
              r'/$fhirpath?resourceType=Patient&resourceId=fp&expression='
                  '${Uri.encodeQueryComponent(nested(7))}',
              authToken: token,
            ),
          )
    ),
    (
      'transform-quick',
      5,
      () async => handler(
            testRequest(
              'POST',
              r'/$transform',
              authToken: token,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'map': map("'b'"),
                'source': {'resourceType': 'Patient', 'id': 'a'},
              }),
            ),
          )
    ),
    (
      'transform-nested7',
      1,
      () async => handler(
            testRequest(
              'POST',
              r'/$transform',
              authToken: token,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'map': map('${nested(7)}.toString()'),
                'source': {'resourceType': 'Patient', 'id': 'a'},
              }),
            ),
          )
    ),
  ];
  for (final (name, runs, call) in programs) {
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      final r = await call();
      sw.stop();
      final status = (r as dynamic).statusCode;
      final line = '$name\t$i\t${sw.elapsedMilliseconds}\t$status\n';
      out.writeAsStringSync(line, mode: FileMode.append, flush: true);
      stdout.write(line);
    }
  }
  await db.close();
  exit(0);
}
