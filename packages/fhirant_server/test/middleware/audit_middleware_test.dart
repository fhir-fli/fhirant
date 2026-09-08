import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/middlewares/audit_middleware.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

void main() {
  late MockFhirAntDb mockDb;
  late Middleware middleware;
  late AuditQueue queue;

  setUpAll(() {
    registerFallbackValue(const fhir.Patient());
    registerFallbackValue(<fhir.Resource>[]);
  });

  setUp(() {
    mockDb = MockFhirAntDb();
    queue = AuditQueue(mockDb);
    middleware = auditMiddleware(mockDb, queue: queue);

    // Default stub: accept any batch write
    when(() => mockDb.saveResources(any())).thenAnswer((_) async => true);
    // The audit trail resolves the subject of care before writing (F10).
    when(() => mockDb.subjectOfCare(any(), any()))
        .thenAnswer((_) async => null);
  });

  Handler wrapHandler({
    int statusCode = 200,
    String body = '{"resourceType":"Patient"}',
    Map<String, Object>? context,
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

  /// The events written so far, once the queue has flushed them.
  Future<List<fhir.Resource>> savedAuditEvents() async {
    // The event is built after the response, asynchronously; give it a turn.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await queue.drain();
    final batches = verify(() => mockDb.saveResources(captureAny())).captured;
    return [
      for (final batch in batches) ...(batch as List<fhir.Resource>),
    ];
  }

  group('auditMiddleware', () {
    test('audit event created on POST (action=C, subtype=create)', () async {
      final handler = wrapHandler();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      final captured = await savedAuditEvents();
      expect(captured, isNotEmpty);

      final auditEvent = captured.last;
      final json = auditEvent.toJson();
      expect(json['resourceType'], equals('AuditEvent'));
      expect(json['action'], equals('C'));
      expect(json['subtype'][0]['code'], equals('create'));
    });

    test('audit event created on GET by ID (action=R, subtype=read)', () async {
      final handler = wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      expect(captured, isNotEmpty);

      final json = captured.last.toJson();
      expect(json['action'], equals('R'));
      expect(json['subtype'][0]['code'], equals('read'));
      expect(json['entity'][0]['what']['reference'], equals('Patient/123'));
    });

    test('audit event created on PUT (action=U, subtype=update)', () async {
      final handler = wrapHandler();
      final request = Request(
        'PUT',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['action'], equals('U'));
      expect(json['subtype'][0]['code'], equals('update'));
    });

    test('audit event created on DELETE (action=D, subtype=delete)', () async {
      final handler = wrapHandler(statusCode: 204, body: '');
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['action'], equals('D'));
      expect(json['subtype'][0]['code'], equals('delete'));
    });

    test('failed request records minor failure outcome (4xx)', () async {
      final handler = wrapHandler(statusCode: 404);
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/999'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['outcome'], equals('4'));
    });

    test('server error records serious failure outcome (5xx)', () async {
      final handler = wrapHandler(statusCode: 500);
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient/123'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['outcome'], equals('8'));
    });

    test('auth user captured in agent (username from context)', () async {
      final handler = wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        context: {
          'auth_user': {'username': 'dr_smith', 'role': 'admin'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['agent'][0]['who']['display'], equals('dr_smith'));
      // No fragment reference — display-only is spec-compliant
      expect(json['agent'][0]['who']['reference'], isNull);
      expect(json['source']['observer']['reference'], isNull);
    });

    test('anonymous agent when no auth_user in context', () async {
      final handler = wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['agent'][0]['who']['display'], equals('anonymous'));
    });

    test('type-level request has no entity (no bare resource type ref)',
        () async {
      final handler = wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/Patient'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['entity'], isNull);
    });

    test('_search request has no entity', () async {
      final handler = wrapHandler();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/Patient/_search'),
        context: {
          'auth_user': {'username': 'doc', 'role': 'clinician'},
        },
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final captured = await savedAuditEvents();
      final json = captured.last.toJson();
      expect(json['entity'], isNull);
    });

    test('metadata requests not audited', () async {
      final handler = wrapHandler();
      final request = Request(
        'GET',
        Uri.parse('http://localhost:8080/metadata'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await queue.drain();
      verifyNever(() => mockDb.saveResources(any()));
    });

    test('AuditEvent POST not audited (infinite loop prevention)', () async {
      final handler = wrapHandler();
      final request = Request(
        'POST',
        Uri.parse('http://localhost:8080/AuditEvent'),
      );

      await handler(request);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await queue.drain();
      verifyNever(() => mockDb.saveResources(any()));
    });
  });
}
