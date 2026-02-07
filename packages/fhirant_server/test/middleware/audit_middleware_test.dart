import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:shelf/shelf.dart';
import 'package:fhirant_server/src/middlewares/audit_middleware.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;
  late Middleware middleware;

  setUpAll(() {
    registerFallbackValue(fhir.Patient());
  });

  setUp(() {
    mockDb = MockFhirAntDb();
    middleware = auditMiddleware(mockDb);

    // Default stub: accept any saveResource call
    when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);
  });

  Handler _wrapHandler({
    int statusCode = 200,
    String body = '{"resourceType":"Patient"}',
    Map<String, Object>? context,
  }) {
    final inner = (Request request) async {
      return Response(statusCode,
          body: body, headers: {'content-type': 'application/json'});
    };
    return middleware(inner);
  }

  group('auditMiddleware', () {
    test('audit event created on POST (action=C, subtype=create)', () async {
      final handler = _wrapHandler();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      // Allow fire-and-forget to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      expect(captured, isNotEmpty);

      final auditEvent = captured.last as fhir.Resource;
      final json = auditEvent.toJson();
      expect(json['resourceType'], equals('AuditEvent'));
      expect(json['action'], equals('C'));
      expect(json['subtype'][0]['code'], equals('create'));
    });

    test('audit event created on GET by ID (action=R, subtype=read)',
        () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      expect(captured, isNotEmpty);

      final json = (captured.last as fhir.Resource).toJson();
      expect(json['action'], equals('R'));
      expect(json['subtype'][0]['code'], equals('read'));
      expect(json['entity'][0]['what']['reference'], equals('Patient/123'));
    });

    test('audit event created on PUT (action=U, subtype=update)', () async {
      final handler = _wrapHandler();
      final request = Request(
        'PUT',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['action'], equals('U'));
      expect(json['subtype'][0]['code'], equals('update'));
    });

    test('audit event created on DELETE (action=D, subtype=delete)', () async {
      final handler = _wrapHandler(statusCode: 204, body: '');
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['action'], equals('D'));
      expect(json['subtype'][0]['code'], equals('delete'));
    });

    test('failed request records minor failure outcome (4xx)', () async {
      final handler = _wrapHandler(statusCode: 404);
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/999'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['outcome'], equals('4'));
    });

    test('server error records serious failure outcome (5xx)', () async {
      final handler = _wrapHandler(statusCode: 500);
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['outcome'], equals('8'));
    });

    test('auth user captured in agent (username from context)', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        context: {
          'auth_user': {'username': 'dr_smith', 'role': 'admin'}
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['agent'][0]['who']['display'], equals('dr_smith'));
    });

    test('anonymous agent when no auth_user in context', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured =
          verify(() => mockDb.saveResource(captureAny())).captured;
      final json = (captured.last as fhir.Resource).toJson();
      expect(json['agent'][0]['who']['display'], equals('anonymous'));
    });

    test('metadata requests not audited', () async {
      final handler = _wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/metadata'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => mockDb.saveResource(any()));
    });

    test('AuditEvent POST not audited (infinite loop prevention)', () async {
      final handler = _wrapHandler();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/AuditEvent'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verifyNever(() => mockDb.saveResource(any()));
    });
  });
}
