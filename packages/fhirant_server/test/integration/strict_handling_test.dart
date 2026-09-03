import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';

import 'test_helpers.dart';

/// `Prefer: handling=strict` against parameters the server does not implement.
///
/// R4 search.html: "Servers may receive parameters from the client that they
/// do not recognize, or may receive parameters they recognize but do not
/// support... In general, servers SHOULD ignore unknown or unsupported
/// parameters", and a client sending `Prefer: handling=strict` is asking the
/// server to return an error for them instead.
///
/// `_contained` and `_containedType` are the recognised-but-unsupported case:
/// fhirant lists them so a lenient request is not rejected, but nothing acts
/// on them. Silently succeeding under strict handling is the dangerous
/// direction — the client believes it filtered and is handed the unfiltered
/// set, which is more of the record than it asked to see.
///
/// `_filter` was in that list until it was implemented. It is answered now, so
/// strict handling must NOT reject it. An operator inside a filter that this
/// server cannot answer is still a 400, under any Prefer header, for the same
/// reason: returning the unfiltered set would say the filter ran.
void main() {
  Future<void> seed(dynamic db) async {
    for (final id in ['p-alpha', 'p-beta', 'p-gamma']) {
      await db.saveResource(fhir.Patient(id: id.toFhirString));
    }
  }

  test('strict handling rejects a parameter the server does not implement',
      () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    final response = await server.handler(
      testRequest(
        'GET',
        '/Patient?_contained=true',
        authToken: token,
        headers: {'Prefer': 'handling=strict'},
      ),
    );

    expect(
      response.statusCode,
      equals(400),
      reason: 'the client asked to be told about anything unsupported; '
          'answering 200 with the unfiltered set tells it the filter ran',
    );
    final body = jsonDecode(await response.readAsString());
    expect(jsonEncode(body), contains('_contained'));
  });

  test('strict handling accepts _filter, which is implemented', () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    final response = await server.handler(
      testRequest(
        'GET',
        '/Patient?_filter=${Uri.encodeQueryComponent('_id eq p-alpha')}',
        authToken: token,
        headers: {'Prefer': 'handling=strict'},
      ),
    );
    expect(response.statusCode, equals(200));
    final bundle =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect((bundle['entry'] as List?) ?? [], hasLength(1));
  });

  test('strict handling rejects _contained and _containedType', () async {
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    for (final param in ['_contained=true', '_containedType=contained']) {
      final response = await server.handler(
        testRequest(
          'GET',
          '/Patient?$param',
          authToken: token,
          headers: {'Prefer': 'handling=strict'},
        ),
      );
      expect(response.statusCode, equals(400), reason: 'for $param');
    }
  });

  test('lenient handling ignores them and still searches', () async {
    // The spec's default: "servers SHOULD ignore unknown or unsupported
    // parameters". Rejecting by default would break clients that send them
    // hopefully.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    for (final headers in [
      <String, String>{},
      {'Prefer': 'handling=lenient'},
    ]) {
      final response = await server.handler(
        testRequest(
          'GET',
          '/Patient?_contained=true',
          authToken: token,
          headers: headers,
        ),
      );
      expect(response.statusCode, equals(200), reason: 'headers: $headers');
      final bundle =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(
        (bundle['entry'] as List?) ?? [],
        hasLength(3),
        reason: 'ignored means ignored: all three patients come back',
      );
    }
  });

  test('an operator _filter cannot answer is a 400 even under lenient',
      () async {
    // Lenient asks the server to ignore what it does not support. It cannot
    // ignore half a filter: dropping the condition returns every patient and
    // tells the client its filter ran.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    for (final headers in [
      <String, String>{},
      {'Prefer': 'handling=lenient'},
    ]) {
      final response = await server.handler(
        testRequest(
          'GET',
          '/Patient?_filter=${Uri.encodeQueryComponent('name eq "alpha"')}',
          authToken: token,
          headers: headers,
        ),
      );
      expect(response.statusCode, equals(400), reason: 'headers: $headers');
    }
  });

  test('strict handling still accepts the parameters that are implemented',
      () async {
    // The rejection must be scoped to what is genuinely unsupported, or
    // strict handling becomes unusable.
    final server = await createTestServer();
    final token = generateTestToken(scopes: ['user/*.cruds']);
    await seed(server.db);

    final response = await server.handler(
      testRequest(
        'GET',
        '/Patient?_summary=count&_count=2',
        authToken: token,
        headers: {'Prefer': 'handling=strict'},
      ),
    );
    expect(response.statusCode, equals(200));
  });
}
