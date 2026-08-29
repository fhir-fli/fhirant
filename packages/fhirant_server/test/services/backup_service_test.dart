import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';
import 'package:test/test.dart';

/// The export and restore the app runs, without HTTP.
///
/// This is the device-to-device path: the at-rest key is sealed in platform
/// secure storage and cannot travel with the data, so a passphrase-wrapped
/// export is the only way a record survives the phone holding it. These run
/// against a real database because the thing worth proving is that the
/// records come back, not that a method was called.
void main() {
  late FhirAntDb db;

  setUp(() {
    db = FhirAntDb(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed() async {
    await db.saveResource(
      fhir.Patient(
        id: 'pat-1'.toFhirString,
        name: [fhir.HumanName(family: 'Okello'.toFhirString)],
      ),
    );
    await db.saveResource(
      fhir.Observation(
        id: 'obs-1'.toFhirString,
        status: fhir.ObservationStatus.final_,
        code: fhir.CodeableConcept(text: 'weight'.toFhirString),
        subject: fhir.Reference(reference: 'Patient/pat-1'.toFhirString),
      ),
    );
  }

  test('an export restores onto an empty device', () async {
    // The whole point: the phone died, this is the replacement.
    await seed();
    final envelope = await BackupService.create(db, 'correct horse battery');

    final replacement = FhirAntDb(NativeDatabase.memory());
    final result = await BackupService.restore(
      replacement,
      envelope,
      passphrase: 'correct horse battery',
    );

    expect(result.saved, equals(2));
    expect(result.failed, isZero);
    final patient =
        await replacement.getResource(fhir.R4ResourceType.Patient, 'pat-1');
    expect(patient, isNotNull);
    expect(
      (patient! as fhir.Patient).name?.first.family?.valueString,
      equals('Okello'),
    );
    await replacement.close();
  });

  test('the exported file carries no readable patient data', () async {
    // It is expected to sit on removable media.
    await seed();
    final envelope = await BackupService.create(db, 'correct horse battery');
    expect(envelope, isNot(contains('Okello')));
    expect(envelope, isNot(contains('pat-1')));
    expect(envelope, isNot(contains('correct horse battery')));
  });

  test('a wrong passphrase does not open it', () async {
    await seed();
    final envelope = await BackupService.create(db, 'correct horse battery');
    final replacement = FhirAntDb(NativeDatabase.memory());
    await expectLater(
      BackupService.restore(
        replacement,
        envelope,
        passphrase: 'correct horse battery staple',
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
    await replacement.close();
  });

  test('an encrypted file with no passphrase is refused, not guessed at',
      () async {
    await seed();
    final envelope = await BackupService.create(db, 'correct horse battery');
    await expectLater(
      BackupService.restore(db, envelope),
      throwsA(isA<BackupPassphraseRequired>()),
    );
  });

  test('an export cannot be made without a passphrase', () async {
    // An unencrypted export would undo the at-rest protection at the exact
    // moment the record is most exposed.
    await seed();
    await expectLater(
      BackupService.create(db, ''),
      throwsA(isA<BackupPassphraseRequired>()),
    );
  });

  test('a plain FHIR Bundle restores without a passphrase', () async {
    // Importing FHIR produced elsewhere is legitimate, and refusing it would
    // not make anything safer since the caller already holds the data.
    final bundle = jsonEncode(
      fhir.Bundle(
        type: fhir.BundleType.collection,
        entry: [
          fhir.BundleEntry(
            resource: fhir.Patient(id: 'imported'.toFhirString),
          ),
        ],
      ).toJson(),
    );
    final result = await BackupService.restore(db, bundle);
    expect(result.saved, equals(1));
    expect(
      await db.getResource(fhir.R4ResourceType.Patient, 'imported'),
      isNotNull,
    );
  });

  test('a file that is not FHIR is reported, not swallowed', () async {
    await expectLater(
      BackupService.restore(db, '{"resourceType":"Patient"}'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      BackupService.restore(db, 'not json at all'),
      throwsA(isA<FormatException>()),
    );
  });

  test('an empty database exports and restores to nothing', () async {
    final envelope = await BackupService.create(db, 'correct horse battery');
    final replacement = FhirAntDb(NativeDatabase.memory());
    final result = await BackupService.restore(
      replacement,
      envelope,
      passphrase: 'correct horse battery',
    );
    expect(result.saved, isZero);
    expect(result.failed, isZero);
    await replacement.close();
  });

  test('a restore reports what it could not take rather than aborting',
      () async {
    // One bad entry must not turn into no record at all.
    final bundle = jsonEncode({
      'resourceType': 'Bundle',
      'type': 'collection',
      'entry': [
        {
          'resource': {'resourceType': 'Patient', 'id': 'good-1'},
        },
        <String, dynamic>{},
        {
          'resource': {'resourceType': 'Patient', 'id': 'good-2'},
        },
      ],
    });
    final result = await BackupService.restore(db, bundle);
    expect(result.saved, equals(2));
    expect(result.failed, equals(1));
    expect(result.failures.single, contains('no resource'));
    for (final id in ['good-1', 'good-2']) {
      expect(
        await db.getResource(fhir.R4ResourceType.Patient, id),
        isNotNull,
        reason: 'a sibling entry failing must not discard $id',
      );
    }
  });

  test('two exports of the same data differ', () async {
    // Fresh salt and nonce per export: identical ciphertext would leak that
    // nothing changed between two backups.
    await seed();
    final first = await BackupService.create(db, 'correct horse battery');
    final second = await BackupService.create(db, 'correct horse battery');
    expect(first, isNot(equals(second)));
  });
}
