import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/fhirant_server.dart';
import 'package:fhirant_server/src/utils/db_resource_cache.dart';
import 'package:fhirant_server/src/utils/host_resource_cache.dart';
import 'package:fhirant_server/src/utils/program_sandbox.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 A9. A client's program (`$fhirpath`, `$cql`,
/// `Library/$evaluate`) ran on the server's isolate with no deadline: a
/// 293-character FHIRPath expression (six nested `select`s over ten
/// literals) held the handler 1,002 ms, and each further 48 characters
/// multiplied that by ten; while it ran nothing else was served. Programs
/// now run in a worker isolate under a deadline, and the worker is killed
/// when the deadline passes.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;
  const deadline = Duration(milliseconds: 300);

  setUp(() async {
    db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final server = FhirAntServer(
      db,
      jwtSecret: testJwtSecret,
      programDeadline: deadline,
    );
    handler = server.createHandler(server.createRouter());
    token = await issueTestToken(db, role: 'admin', scopes: ['system/*.*']);
    await db.saveResource(fhir.Patient(id: 'fp'.toFhirString));
  });
  tearDown(() => db.close());

  /// The review's expression at [depth]: 10^depth evaluations.
  String nested(int depth) {
    const d = '(0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9)';
    var expr = r'$this';
    for (var i = 0; i < depth; i++) {
      expr = '$d.select($expr)';
    }
    return '$expr.count()';
  }

  Future<Response> fhirpath(String expression) async => handler(
        testRequest(
          'GET',
          r'/$fhirpath?resourceType=Patient&resourceId=fp&expression='
              '${Uri.encodeQueryComponent(expression)}',
          authToken: token,
        ),
      );

  test('a program past the deadline is refused, and the server goes on',
      () async {
    final sw = Stopwatch()..start();
    // Depth 7: 10^7 evaluations, ten times the review's one-second case.
    final res = await fhirpath(nested(7));
    final text = await res.readAsString();
    expect(res.statusCode, 422, reason: text);
    expect(
      (jsonDecode(text) as Map<String, dynamic>)['issue'][0]['code'],
      'too-costly',
    );
    // Refused at the deadline, not when the program would have finished.
    expect(sw.elapsedMilliseconds, lessThan(deadline.inMilliseconds * 5));
    // The worker is dead and the server answers the next request.
    final quick = await fhirpath('id');
    expect(quick.statusCode, 200);
    expect(jsonDecode(await quick.readAsString()), [
      {'value': 'fp'},
    ]);
  });

  test('a program within the deadline answers as before', () async {
    final res = await fhirpath(nested(3));
    final text = await res.readAsString();
    expect(res.statusCode, 200, reason: text);
    expect(jsonDecode(text), [
      {'value': 1000},
    ]);
  });

  test('an expression that does not parse is still a 400', () async {
    final res = await fhirpath('name.where(');
    expect(res.statusCode, 400);
  });

  test(r'$cql runs under the deadline too', () async {
    // A define whose evaluation cannot finish in time: a seven-way
    // cartesian query, 10^7 rows.
    const ten = '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}';
    const slow = "library P version '1.0.0'\n"
        'define X: Count(from ($ten) A, ($ten) B, ($ten) C, ($ten) D, '
        '($ten) E, ($ten) F, ($ten) G return 1)';
    final res = await handler(
      testRequest(
        'POST',
        r'/$cql',
        authToken: token,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'cql': slow}),
      ),
    );
    final text = await res.readAsString();
    expect(res.statusCode, 422, reason: text);
    final ok = await handler(
      testRequest(
        'POST',
        r'/$cql',
        authToken: token,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'cql': "library P version '1.0.0'\ndefine X: 1 + 1"}),
      ),
    );
    final okText = await ok.readAsString();
    expect(ok.statusCode, 200, reason: okText);
    expect(okText, contains('"valueInteger":2'));
  });

  test(r'$transform runs under the deadline too', () async {
    // A map whose one rule evaluates the review's expression at depth 7.
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
    Future<Response> transform(String expression) async => handler(
          testRequest(
            'POST',
            r'/$transform',
            authToken: token,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'map': map(expression),
              'source': {'resourceType': 'Patient', 'id': 'a'},
            }),
          ),
        );
    final slow = await transform('${nested(7)}.toString()');
    final text = await slow.readAsString();
    expect(slow.statusCode, 422, reason: text);
    expect(
      (jsonDecode(text) as Map<String, dynamic>)['issue'][0]['code'],
      'too-costly',
    );
    final quick = await transform("'b'");
    final quickText = await quick.readAsString();
    expect(quick.statusCode, 200, reason: quickText);
    expect(jsonDecode(quickText), {'resourceType': 'Patient', 'id': 'b'});
  });

  group('runHostedProgram', () {
    test('the host answers the program from this isolate', () async {
      final answered = <Object?>[];
      final result = await runHostedProgram(
        (host) async {
          final a = await askHost(host, 'first');
          final b = await askHost(host, 'second');
          return '$a,$b';
        },
        deadline: const Duration(seconds: 5),
        host: (request) async {
          answered.add(request);
          return 'answer to $request';
        },
      );
      expect(result, 'answer to first,answer to second');
      expect(answered, ['first', 'second']);
    });

    test("a host that throws is the server's failure, not the program's",
        () async {
      await expectLater(
        runHostedProgram(
          (host) => askHost(host, 'x'),
          deadline: const Duration(seconds: 5),
          host: (_) => throw StateError('store gone'),
        ),
        throwsA(
          isA<ProgramHostFailed>()
              .having((e) => '${e.error}', 'error', contains('store gone')),
        ),
      );
    });

    test('a HostResourceCache resolves a stored canonical through the host',
        () async {
      const url = 'http://example.org/StructureDefinition/Held';
      await db.saveResource(
        fhir.StructureDefinition(
          url: url.toFhirUri,
          name: 'Held'.toFhirString,
          status: fhir.PublicationStatus.active,
          kind: fhir.StructureDefinitionKind.resource,
          abstract_: false.toFhirBoolean,
          type: 'Patient'.toFhirUri,
        ),
      );
      final cache = DbResourceCache(db);
      final found = await runHostedProgram(
        (host) async {
          final worker = HostResourceCache(host);
          final sd = await worker.getStructureDefinition(url);
          final names = await worker.getResourceNames();
          final missing = await worker.getStructureDefinition(
            'http://example.org/StructureDefinition/NotHeld',
          );
          return (sd?.type.valueString, names.contains('Held'), missing);
        },
        deadline: const Duration(seconds: 10),
        host: (request) => serveResourceCache(cache, request),
      );
      expect(found, ('Patient', true, null));
    });
  });

  group('runProgram', () {
    test("returns the program's value", () async {
      expect(
        await runProgram(() => 2 + 2, deadline: const Duration(seconds: 5)),
        4,
      );
    });

    test('kills the worker at the deadline', () async {
      final sw = Stopwatch()..start();
      await expectLater(
        runProgram(
          () {
            var x = 0;
            while (true) {
              x++;
            }
            // ignore: dead_code
            return x;
          },
          deadline: const Duration(milliseconds: 200),
        ),
        throwsA(isA<ProgramTimeout>()),
      );
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test("a program's own error comes back as ProgramFailed", () async {
      await expectLater(
        runProgram(
          () => throw StateError('no'),
          deadline: const Duration(seconds: 5),
        ),
        throwsA(isA<ProgramFailed>()),
      );
    });
  });
}
