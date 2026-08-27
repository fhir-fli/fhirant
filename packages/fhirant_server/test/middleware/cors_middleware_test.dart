import 'package:fhirant_server/src/middlewares/cors_middleware.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('corsMiddleware', () {
    late Middleware middleware;

    setUp(() {
      middleware = corsMiddleware();
    });

    Handler wrapHandler({
      int statusCode = 200,
      String body = '{"resourceType":"Patient"}',
    }) {
      Future<Response> inner(Request request) async {
        return Response(
          statusCode,
          body: body,
          headers: {'content-type': 'application/json'},
        );
      }

      return middleware(inner);
    }

    /// A handler wired with an explicit wide-open policy, which is what the
    /// default used to be. Kept because publishing `*` is still a supported
    /// choice — it is just no longer one an operator inherits silently.
    Handler wrapPermissive() {
      final permissive =
          corsMiddleware(config: const CorsConfig(allowOrigin: '*'));
      return permissive(
        (request) async =>
            Response.ok('ok', headers: {'content-type': 'application/json'}),
      );
    }

    test('OPTIONS preflight returns 204 with CORS headers when a policy is set',
        () async {
      final handler = wrapPermissive();
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);

      expect(response.statusCode, equals(204));
      expect(response.headers['access-control-allow-origin'], equals('*'));
      expect(response.headers['access-control-allow-methods'], isNotNull);
      expect(response.headers['access-control-allow-headers'], isNotNull);
    });

    test('GET response includes CORS headers when a policy is set', () async {
      final handler = wrapPermissive();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['access-control-allow-origin'], equals('*'));
    });

    test('POST response includes CORS headers when a policy is set', () async {
      final handler = wrapPermissive();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['access-control-allow-origin'], equals('*'));
    });

    test('custom allowed origin is used', () async {
      final customMiddleware = corsMiddleware(
        config: const CorsConfig(allowOrigin: 'https://example.com'),
      );
      final handler = customMiddleware((request) async {
        return Response.ok('ok', headers: {'content-type': 'application/json'});
      });

      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);

      expect(
        response.headers['access-control-allow-origin'],
        equals('https://example.com'),
      );
    });

    test('Expose-Headers lists FHIR headers', () async {
      final handler = wrapPermissive();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);
      final exposeHeaders =
          response.headers['access-control-expose-headers'] ?? '';

      expect(exposeHeaders, contains('Content-Location'));
      expect(exposeHeaders, contains('ETag'));
      expect(exposeHeaders, contains('Last-Modified'));
      expect(exposeHeaders, contains('Location'));
    });

    test('Allow-Headers lists required headers', () async {
      final handler = wrapPermissive();
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);
      final allowHeaders =
          response.headers['access-control-allow-headers'] ?? '';

      expect(allowHeaders, contains('Authorization'));
      expect(allowHeaders, contains('Content-Type'));
      expect(allowHeaders, contains('Accept'));
      expect(allowHeaders, contains('Prefer'));
      expect(allowHeaders, contains('If-Match'));
      expect(allowHeaders, contains('If-None-Exist'));
    });

    test('Allow-Methods lists all HTTP methods', () async {
      final handler = wrapPermissive();
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);
      final allowMethods =
          response.headers['access-control-allow-methods'] ?? '';

      expect(allowMethods, contains('GET'));
      expect(allowMethods, contains('POST'));
      expect(allowMethods, contains('PUT'));
      expect(allowMethods, contains('PATCH'));
      expect(allowMethods, contains('DELETE'));
      expect(allowMethods, contains('OPTIONS'));
    });

    test('Max-Age is present with configured value', () async {
      final handler = wrapPermissive();
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:8080/Patient'),
      );

      final response = await handler(request);

      expect(response.headers['access-control-max-age'], equals('86400'));
    });
    test('by default no cross-origin policy is published', () async {
      // Bearer-token auth means a wide-open policy does not leak authenticated
      // data by itself. What it does do is let any page the operator visits
      // use their browser to reach this server on their local network — which
      // the page's author cannot reach directly — and read what comes back.
      // Publishing nothing is the safer starting point; a browser client is an
      // explicit choice.
      final handler = wrapHandler();
      final response = await handler(
        Request('GET', Uri.parse('http://localhost:8080/Patient')),
      );

      expect(response.headers['access-control-allow-origin'], isNull);
      expect(response.headers['access-control-allow-methods'], isNull);
      expect(response.headers['access-control-expose-headers'], isNull);
    });

    test('preflight is still answered when no policy is published', () async {
      // A well-formed answer without permission in it, rather than falling
      // through to the router and confusing the caller with a 404.
      final handler = wrapHandler();
      final response = await handler(
        Request('OPTIONS', Uri.parse('http://localhost:8080/Patient')),
      );

      expect(response.statusCode, equals(204));
      expect(response.headers['access-control-allow-origin'], isNull);
    });

    test('the request still reaches the handler without a policy', () async {
      // CORS is a browser rule, not an access control. A non-browser client
      // is unaffected, which is the point: this must not break device to
      // device use.
      final handler = wrapHandler();
      final response = await handler(
        Request('GET', Uri.parse('http://localhost:8080/Patient')),
      );

      expect(response.statusCode, equals(200));
      expect(await response.readAsString(), contains('Patient'));
    });
  });
}
