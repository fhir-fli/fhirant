import 'dart:convert';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/middlewares/content_negotiation.dart';

void main() {
  group('contentNegotiationMiddleware', () {
    late Middleware middleware;

    setUp(() {
      middleware = contentNegotiationMiddleware();
    });

    Handler _wrapHandler({
      String contentType = 'application/json',
      String body = '{"resourceType":"Patient"}',
    }) {
      final inner = (Request request) async {
        return Response.ok(body, headers: {'content-type': contentType});
      };
      return middleware(inner);
    }

    test('rewrites Content-Type to application/fhir+json', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'accept': '*/*'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(
        response.headers['content-type'],
        contains('application/fhir+json'),
      );
    });

    test('Accept: application/fhir+json passes through', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'accept': 'application/fhir+json'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(
        response.headers['content-type'],
        contains('application/fhir+json'),
      );
    });

    test('Accept: application/xml returns 406', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'accept': 'application/xml'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(406));
      final body = await response.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['resourceType'], equals('OperationOutcome'));
    });

    test('Accept: application/fhir+xml returns 406', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        headers: {'accept': 'application/fhir+xml'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(406));
    });

    test('_format=json overrides Accept header', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient?_format=json'),
        headers: {'accept': 'application/xml'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
    });

    test('non-JSON responses not rewritten', () async {
      final handler = _wrapHandler(
        contentType: 'text/plain',
        body: 'hello',
      );
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/something'),
        headers: {'accept': '*/*'},
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('text/plain'));
    });
  });
}
