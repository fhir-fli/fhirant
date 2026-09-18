import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// REVIEW-2026-09-17 T1 and T2.
///
/// T1: "this server does not hold that CodeSystem" was answered as "no such
/// code": `$expand` 200 with total 0, `$validate-code` result=false, `:in`
/// nothing, `:not-in` everything.
///
/// R4B valueset-operation-expand.html, read whole 2026-09-17, verbatim:
/// "When a server cannot correctly expand a value set because it does not
/// fully understand the code systems (e.g. it has the wrong version, or
/// incomplete definitions) then it SHALL return an error."
///
/// R4B codesystem-operation-validate-code.html, read whole 2026-09-17, the
/// heading of its error example, verbatim: "When the validation cannot be
/// performed. An error like this not returned if the code is not valid, but
/// when the server is unable to determine whether the code is valid". The
/// OperationDefinition's out parameters (profiles-resources.json) are
/// result, message and display, so "cannot tell" has no place in a
/// Parameters answer and is an OperationOutcome.
///
/// T2: `$validate-code` answered true for a code the compose excludes,
/// because it kept its own copy of the expansion. All three now use the
/// store's.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String token;

  const loinc = 'http://loinc.org';
  const vsUrl = 'http://example.org/ValueSet/all-loinc';

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    token = await issueTestToken(
      db,
      username: 't1-admin',
      role: 'admin',
      scopes: ['system/*.*'],
    );
  });
  tearDown(() => db.close());

  Future<Response> send(String method, String path, {Object? body}) async =>
      handler(
        testRequest(
          method,
          path,
          body: body == null ? null : jsonEncode(body),
          headers: {'content-type': 'application/fhir+json'},
          authToken: token,
        ),
      );

  Future<void> put(Map<String, dynamic> r) async {
    final res = await send('PUT', '/${r['resourceType']}/${r['id']}', body: r);
    expect(res.statusCode, anyOf(200, 201), reason: await res.readAsString());
  }

  /// The body as an OperationOutcome with one error issue, as the published
  /// examples are shaped (examples-json.zip,
  /// operationoutcome-example-exception.json: `issue[].severity`, `code`,
  /// and text for a human): returns the issue code.
  Future<String> refusal(Response res, {required int status}) async {
    final text = await res.readAsString();
    expect(res.statusCode, status, reason: text);
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json['resourceType'], 'OperationOutcome', reason: text);
    final issue = (json['issue'] as List).single as Map<String, dynamic>;
    expect(issue['severity'], 'error');
    expect(
      '${issue['diagnostics'] ?? (issue['details'] as Map?)?['text']}',
      isNot('null'),
    );
    return issue['code'] as String;
  }

  Map<String, dynamic> valueSet(Map<String, dynamic> compose) => {
        'resourceType': 'ValueSet',
        'id': 'vs',
        'url': vsUrl,
        'status': 'active',
        'compose': compose,
      };

  Map<String, dynamic> observation(String id, String code) => {
        'resourceType': 'Observation',
        'id': id,
        'status': 'final',
        'code': {
          'coding': [
            {'system': loinc, 'code': code},
          ],
        },
      };

  group('T1: a ValueSet that includes all of a CodeSystem not held', () {
    setUp(() async {
      await put(
        valueSet({
          'include': [
            {'system': loinc},
          ],
        }),
      );
      await put(observation('o1', '8867-4'));
    });

    test(r'$expand is an error, not an empty expansion', () async {
      expect(
        await refusal(await send('GET', r'/ValueSet/vs/$expand'), status: 422),
        'not-found',
      );
      expect(
        await refusal(
          await send(
            'GET',
            '/ValueSet/\$expand?url=${Uri.encodeQueryComponent(vsUrl)}',
          ),
          status: 422,
        ),
        'not-found',
      );
    });

    test(r'ValueSet/$validate-code is an error, not result=false', () async {
      expect(
        await refusal(
          await send(
            'GET',
            '/ValueSet/vs/\$validate-code?system=$loinc&code=8867-4',
          ),
          status: 422,
        ),
        'not-found',
      );
    });

    test(':in and :not-in are errors, not nothing and everything', () async {
      for (final modifier in ['in', 'not-in']) {
        expect(
          await refusal(
            await send(
              'GET',
              '/Observation?code:$modifier='
                  '${Uri.encodeQueryComponent(vsUrl)}',
            ),
            status: 400,
          ),
          'not-found',
          reason: modifier,
        );
      }
    });
  });

  test(':in a ValueSet the server does not hold is an error', () async {
    await put(observation('o1', '8867-4'));
    for (final modifier in ['in', 'not-in']) {
      expect(
        await refusal(
          await send(
            'GET',
            '/Observation?code:$modifier='
                '${Uri.encodeQueryComponent('http://example.org/none')}',
          ),
          status: 400,
        ),
        'not-found',
        reason: modifier,
      );
    }
  });

  test(r'CodeSystem/$validate-code of a system not held is an error', () async {
    expect(
      await refusal(
        await send(
          'GET',
          '/CodeSystem/\$validate-code?system=$loinc&code=8867-4',
        ),
        status: 404,
      ),
      'not-found',
    );
  });

  test(r'ValueSet/$validate-code of a url not held is an error', () async {
    expect(
      await refusal(
        await send(
          'GET',
          r'/ValueSet/$validate-code'
              '?url=${Uri.encodeQueryComponent('http://example.org/none')}'
              '&system=$loinc&code=8867-4',
        ),
        status: 404,
      ),
      'not-found',
    );
  });

  group('a CodeSystem held as a fragment', () {
    setUp(() async {
      await put({
        'resourceType': 'CodeSystem',
        'id': 'frag',
        'url': loinc,
        'status': 'active',
        'content': 'fragment',
        'concept': [
          {'code': '8867-4', 'display': 'Heart rate'},
        ],
      });
    });

    test('a code it lists is valid', () async {
      final res = await send(
        'GET',
        '/CodeSystem/\$validate-code?system=$loinc&code=8867-4',
      );
      expect(res.statusCode, 200);
      final params = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['parameter'] as List;
      expect(
        params.firstWhere((p) => (p as Map)['name'] == 'result'),
        containsPair('valueBoolean', true),
      );
    });

    test('a code it does not list cannot be called invalid', () async {
      expect(
        await refusal(
          await send(
            'GET',
            '/CodeSystem/\$validate-code?system=$loinc&code=8480-6',
          ),
          status: 422,
        ),
        'not-supported',
      );
    });

    test(r'a ValueSet including all of it does not $expand', () async {
      await put(
        valueSet({
          'include': [
            {'system': loinc},
          ],
        }),
      );
      expect(
        await refusal(await send('GET', r'/ValueSet/vs/$expand'), status: 422),
        'not-supported',
      );
    });
  });

  group('T2: compose.exclude', () {
    setUp(() async {
      await put({
        'resourceType': 'CodeSystem',
        'id': 'cs',
        'url': 'http://example.org/cs',
        'status': 'active',
        'content': 'complete',
        'concept': [
          {'code': 'a', 'display': 'A'},
          {'code': 'b', 'display': 'B'},
        ],
      });
      await put(
        valueSet({
          'include': [
            {'system': 'http://example.org/cs'},
          ],
          'exclude': [
            {
              'system': 'http://example.org/cs',
              'concept': [
                {'code': 'a'},
              ],
            },
          ],
        }),
      );
    });

    Future<Map<String, dynamic>> validate(String code) async {
      final res = await send(
        'GET',
        '/ValueSet/vs/\$validate-code?system=http://example.org/cs&code=$code',
      );
      expect(res.statusCode, 200);
      final params = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['parameter'] as List;
      return {
        for (final p in params.cast<Map<String, dynamic>>())
          p['name'] as String: p['valueBoolean'] ?? p['valueString'],
      };
    }

    test(r'$expand and $validate-code agree on the excluded code', () async {
      final res = await send('GET', r'/ValueSet/vs/$expand');
      expect(res.statusCode, 200);
      final expansion = (jsonDecode(await res.readAsString())
          as Map<String, dynamic>)['expansion'] as Map<String, dynamic>;
      expect(
        (expansion['contains'] as List).map((c) => (c as Map)['code']),
        ['b'],
      );
      expect((await validate('a'))['result'], isFalse);
      final b = await validate('b');
      expect(b['result'], isTrue);
      expect(b['display'], 'B');
    });
  });

  // REVIEW-2026-09-17 Q8, through the pipeline: a code element's implicit
  // system (fhir_r4 enums carry their CodeSystem since 0b73e0818).
  test('status:in and status=<system>|code match a code element', () async {
    await put(observation('o1', '8867-4'));
    await put({
      'resourceType': 'ValueSet',
      'id': 'final-only',
      'url': 'http://example.org/ValueSet/final-only',
      'status': 'active',
      'compose': {
        'include': [
          {
            'system': 'http://hl7.org/fhir/observation-status',
            'concept': [
              {'code': 'final'},
            ],
          },
        ],
      },
    });
    Future<int> total(String query) async {
      final res = await send('GET', '/Observation?$query');
      final text = await res.readAsString();
      expect(res.statusCode, 200, reason: text);
      return (jsonDecode(text) as Map<String, dynamic>)['total'] as int;
    }

    const finalOnly = 'http://example.org/ValueSet/final-only';
    final encoded = Uri.encodeQueryComponent(finalOnly);
    expect(
      await total('status=http://hl7.org/fhir/observation-status|final'),
      1,
    );
    expect(await total('status=http://example.org/other|final'), 0);
    expect(await total('status:in=$encoded'), 1);
    expect(await total('status:not-in=$encoded'), 0);
  });
}
