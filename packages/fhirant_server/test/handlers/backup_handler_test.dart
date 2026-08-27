import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/handlers/backup_handler.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class MockFhirAntDb extends Mock implements FhirAntDb {}

const _passphrase = 'a passphrase the operator chose';

/// A `\$backup` request carrying the passphrase, the way a caller must now
/// send it.
Request _backupRequest({String passphrase = _passphrase}) => Request(
      'POST',
      Uri.parse(r'http://localhost:8080/$backup'),
      body: jsonEncode({
        'resourceType': 'Parameters',
        'parameter': [
          {'name': 'passphrase', 'valueString': passphrase},
        ],
      }),
    );

void main() {
  late MockFhirAntDb mockDb;

  setUpAll(() {
    registerFallbackValue(const fhir.Patient());
    registerFallbackValue(fhir.R4ResourceType.Patient);
  });

  setUp(() {
    mockDb = MockFhirAntDb();
    // saveResource commits per call, so the multi-write paths now run inside
    // one database transaction. The mock has to actually run the closure or
    // nothing is written.
    when(() => mockDb.transaction<void>(any())).thenAnswer(
      (invocation) async =>
          (invocation.positionalArguments[0] as Future<void> Function())(),
    );
  });

  group('backupHandler', () {
    test('returns a collection Bundle with resources', () async {
      final patient = fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Smith'.toFhirString)],
      );
      final observation = fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          text: 'Test'.toFhirString,
        ),
      );

      when(() => mockDb.getResourceTypes()).thenAnswer(
        (_) async => [
          fhir.R4ResourceType.Patient,
          fhir.R4ResourceType.Observation,
        ],
      );
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Patient))
          .thenAnswer((_) async => [patient]);
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Observation))
          .thenAnswer((_) async => [observation]);

      final response = await backupHandler(_backupRequest(), mockDb);

      expect(response.statusCode, equals(200));

      // The response is the encrypted envelope, so the Bundle is only
      // reachable through the passphrase.
      final envelope = await response.readAsString();
      expect(envelope, isNot(contains('Bundle')));
      final body = jsonDecode(BackupCrypto.decrypt(envelope, _passphrase))
          as Map<String, dynamic>;
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('collection'));
      expect(body['total'], equals(2));

      final entries = body['entry'] as List;
      expect(entries, hasLength(2));

      // Verify entries contain the resources
      final entryTypes = entries
          .map((e) => (e as Map<String, dynamic>)['resource']['resourceType'])
          .toList();
      expect(entryTypes, contains('Patient'));
      expect(entryTypes, contains('Observation'));

      // Verify fullUrl is set
      final fullUrls =
          entries.map((e) => (e as Map<String, dynamic>)['fullUrl']).toList();
      expect(fullUrls, contains('Patient/p1'));
      expect(fullUrls, contains('Observation/o1'));
    });

    test('returns empty Bundle when DB has no resources', () async {
      when(() => mockDb.getResourceTypes()).thenAnswer((_) async => []);

      final response = await backupHandler(_backupRequest(), mockDb);

      expect(response.statusCode, equals(200));

      final body = jsonDecode(
        BackupCrypto.decrypt(await response.readAsString(), _passphrase),
      ) as Map<String, dynamic>;
      expect(body['resourceType'], equals('Bundle'));
      expect(body['type'], equals('collection'));
      expect(body['total'], equals(0));
      expect(body.containsKey('entry'), isFalse);
    });

    test('returns 500 when DB throws', () async {
      when(() => mockDb.getResourceTypes())
          .thenThrow(Exception('DB connection lost'));

      final response = await backupHandler(_backupRequest(), mockDb);

      expect(response.statusCode, equals(500));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
    });
  });

  group('restoreHandler', () {
    test('saves resources and returns OperationOutcome', () async {
      final patient = fhir.Patient(
        id: 'p1'.toFhirString,
        name: [fhir.HumanName(family: 'Smith'.toFhirString)],
      );
      final observation = fhir.Observation(
        id: 'o1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(
          text: 'Test'.toFhirString,
        ),
      );

      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(resource: patient),
          fhir.BundleEntry(resource: observation),
        ],
      );

      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('application/fhir+json'));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));

      final issues = body['issue'] as List;
      // First issue is the summary
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('2 saved'));
      expect(summary['diagnostics'], contains('0 errors'));

      // Verify saveResource was called twice
      verify(() => mockDb.saveResource(any())).called(2);
    });

    test('returns 400 for empty body', () async {
      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: '',
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect((body['issue'] as List)[0]['diagnostics'], contains('empty'));
    });

    test('returns 400 for invalid JSON', () async {
      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: 'not-json{{{',
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect(
        (body['issue'] as List)[0]['diagnostics'],
        contains('Invalid JSON'),
      );
    });

    test('returns 400 for non-Bundle resource', () async {
      final patient = fhir.Patient(id: 'p1'.toFhirString);

      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: jsonEncode(patient.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(400));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['resourceType'], equals('OperationOutcome'));
      expect(
        (body['issue'] as List)[0]['diagnostics'],
        contains('Expected a Bundle'),
      );
    });

    test('reports errors for entries that fail to save', () async {
      final patient1 = fhir.Patient(id: 'p1'.toFhirString);
      final patient2 = fhir.Patient(id: 'p2'.toFhirString);

      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(resource: patient1),
          fhir.BundleEntry(resource: patient2),
        ],
      );

      // First save succeeds, second fails
      var callCount = 0;
      when(() => mockDb.saveResource(any())).thenAnswer((_) async {
        callCount++;
        return callCount == 1;
      });

      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final issues = body['issue'] as List;
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('1 saved'));
      expect(summary['diagnostics'], contains('1 errors'));
    });

    test('handles entries without resource gracefully', () async {
      final bundle = fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(
            fullUrl: 'urn:uuid:test'.toFhirUri,
          ),
        ],
      );

      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$restore'),
        body: jsonEncode(bundle.toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
      final response = await restoreHandler(request, mockDb);

      expect(response.statusCode, equals(200));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final issues = body['issue'] as List;
      final summary = issues[0] as Map<String, dynamic>;
      expect(summary['diagnostics'], contains('0 saved'));
      expect(summary['diagnostics'], contains('1 errors'));
    });
  });

  group('the backup leaves the device encrypted', () {
    setUp(() {
      when(() => mockDb.getResourceTypes())
          .thenAnswer((_) async => [fhir.R4ResourceType.Patient]);
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Patient))
          .thenAnswer(
        (_) async => [
          fhir.Patient(
            id: 'p1'.toFhirString,
            name: [fhir.HumanName(family: 'Faulkenberry'.toFhirString)],
          ),
        ],
      );
    });

    test('refuses to export without a passphrase', () async {
      final request =
          Request('POST', Uri.parse(r'http://localhost:8080/$backup'));
      final response = await backupHandler(request, mockDb);

      expect(response.statusCode, equals(400));
      verifyNever(() => mockDb.getResourcesByType(any()));
    });

    test('refuses an empty passphrase', () async {
      final response =
          await backupHandler(_backupRequest(passphrase: ''), mockDb);
      expect(response.statusCode, equals(400));
    });

    test('a malformed body is not taken as consent to export in the clear',
        () async {
      final request = Request(
        'POST',
        Uri.parse(r'http://localhost:8080/$backup'),
        body: 'not json at all',
      );
      final response = await backupHandler(request, mockDb);
      expect(response.statusCode, equals(400));
    });

    test('no patient data appears in the response', () async {
      final response = await backupHandler(_backupRequest(), mockDb);
      final envelope = await response.readAsString();

      expect(envelope, isNot(contains('Faulkenberry')));
      expect(envelope, isNot(contains('Patient')));
      expect(envelope, isNot(contains(_passphrase)));
    });

    test('the wrong passphrase cannot open it', () async {
      final response = await backupHandler(_backupRequest(), mockDb);
      final envelope = await response.readAsString();

      expect(
        () => BackupCrypto.decrypt(envelope, 'a different passphrase'),
        throwsA(isA<BackupDecryptionException>()),
      );
    });
  });

  group('restore accepts what backup produced', () {
    test('an encrypted backup round-trips with its passphrase', () async {
      when(() => mockDb.getResourceTypes())
          .thenAnswer((_) async => [fhir.R4ResourceType.Patient]);
      when(() => mockDb.getResourcesByType(fhir.R4ResourceType.Patient))
          .thenAnswer(
        (_) async => [fhir.Patient(id: 'p1'.toFhirString)],
      );
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final envelope =
          await (await backupHandler(_backupRequest(), mockDb)).readAsString();

      final restore = await restoreHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: envelope,
          headers: {'x-backup-passphrase': _passphrase},
        ),
        mockDb,
      );

      expect(restore.statusCode, equals(200));
      verify(() => mockDb.saveResource(any())).called(1);
    });

    test('an encrypted backup without the passphrase is refused', () async {
      final envelope = BackupCrypto.encrypt(
        '{"resourceType":"Bundle","type":"collection"}',
        _passphrase,
      );

      final restore = await restoreHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: envelope,
        ),
        mockDb,
      );

      expect(restore.statusCode, equals(400));
      final body =
          jsonDecode(await restore.readAsString()) as Map<String, dynamic>;
      expect(jsonEncode(body), contains('passphrase'));
    });

    test('an encrypted backup with the wrong passphrase is refused', () async {
      final envelope = BackupCrypto.encrypt(
        '{"resourceType":"Bundle","type":"collection"}',
        _passphrase,
      );

      final restore = await restoreHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: envelope,
          headers: {'x-backup-passphrase': 'wrong'},
        ),
        mockDb,
      );

      expect(restore.statusCode, equals(400));
      verifyNever(() => mockDb.saveResource(any()));
    });

    test('a plain Bundle is still accepted, for importing FHIR from elsewhere',
        () async {
      when(() => mockDb.saveResource(any())).thenAnswer((_) async => true);

      final restore = await restoreHandler(
        Request(
          'POST',
          Uri.parse(r'http://localhost:8080/$restore'),
          body: jsonEncode({
            'resourceType': 'Bundle',
            'type': 'collection',
            'entry': [
              {
                'resource': {'resourceType': 'Patient', 'id': 'imported'},
              },
            ],
          }),
        ),
        mockDb,
      );

      expect(restore.statusCode, equals(200));
    });
  });
}
