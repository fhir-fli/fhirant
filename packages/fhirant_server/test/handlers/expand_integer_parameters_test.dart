import 'dart:convert';

import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../integration/test_helpers.dart';

/// REVIEW-2026-10-06 finding 10 (probe P8): `ValueSet/[id]/$expand` with a
/// Parameters body whose `offset` and `count` are `valueInteger`, the type
/// OperationDefinition ValueSet-expand gives them, was a 500; the query
/// string and `valueString` forms worked.
void main() {
  late FhirAntDb db;
  late Handler handler;
  late String admin;

  setUp(() async {
    final server = await createTestServer();
    db = server.db;
    handler = server.handler;
    admin = await issueTestToken(
      db,
      username: 'adm',
      role: 'admin',
      scopes: ['system/*.*'],
    );
    await handler(
      testRequest(
        'PUT',
        '/CodeSystem/cs1',
        authToken: admin,
        body: jsonEncode({
          'resourceType': 'CodeSystem',
          'id': 'cs1',
          'url': 'http://x/cs',
          'status': 'active',
          'content': 'complete',
          'concept': [
            {'code': 'a'},
            {'code': 'b'},
            {'code': 'c'},
          ],
        }),
      ),
    );
    await handler(
      testRequest(
        'PUT',
        '/ValueSet/vs1',
        authToken: admin,
        body: jsonEncode({
          'resourceType': 'ValueSet',
          'id': 'vs1',
          'url': 'http://x/vs',
          'status': 'active',
          'compose': {
            'include': [
              {'system': 'http://x/cs'},
            ],
          },
        }),
      ),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> expand(Object? offset, Object? count) async {
    final response = await handler(
      testRequest(
        'POST',
        r'/ValueSet/vs1/$expand',
        authToken: admin,
        body: jsonEncode({
          'resourceType': 'Parameters',
          'parameter': [
            {
              'name': 'offset',
              if (offset is int)
                'valueInteger': offset
              else
                'valueString': offset,
            },
            {
              'name': 'count',
              if (count is int) 'valueInteger': count else 'valueString': count,
            },
          ],
        }),
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  test('valueInteger offset and count page the expansion', () async {
    final body = await expand(1, 1);
    final expansion = body['expansion'] as Map<String, dynamic>;
    expect(expansion['total'], 3);
    expect(expansion['offset'], 1);
    final contains = expansion['contains'] as List;
    expect(contains.map((c) => (c as Map)['code']), ['b']);
  });

  test('valueString offset and count page it the same way', () async {
    final body = await expand('1', '1');
    final contains = (body['expansion'] as Map)['contains'] as List;
    expect(contains.map((c) => (c as Map)['code']), ['b']);
  });
}
