import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';

/// Creating and restoring the encrypted export, independent of HTTP.
///
/// This is the device-to-device path: the database is encrypted at rest under
/// a key sealed in platform secure storage, so the key cannot travel with the
/// data. A passphrase-wrapped export is the only way a record survives the
/// death of the phone holding it.
///
/// The logic lives here rather than in the handler because the app performs
/// the same operation without HTTP. It holds the database directly, so making
/// a clinician start a server and authenticate in order to save their own
/// record would be a round trip through a network that a disaster deployment
/// may not have.
class BackupService {
  const BackupService._();

  /// Every stored resource as an encrypted envelope.
  ///
  /// [passphrase] must not be empty. It is the only thing protecting the
  /// result, which is expected to sit on removable media where an attacker
  /// can guess at leisure.
  static Future<String> create(
    FhirAntDb db,
    String passphrase,
  ) async {
    if (passphrase.isEmpty) {
      throw const BackupPassphraseRequired(
        'A backup cannot be created without a passphrase',
      );
    }
    final json = jsonEncode((await bundle(db)).toJson());
    return BackupCrypto.encrypt(json, passphrase);
  }

  /// Every stored resource as a collection Bundle, unencrypted.
  ///
  /// Exposed for the handler, which reports the entry count, and for tests.
  /// Callers that write this anywhere are responsible for protecting it.
  static Future<fhir.Bundle> bundle(FhirAntDb db) async {
    final entries = <fhir.BundleEntry>[];
    for (final resourceType in await db.getResourceTypes()) {
      for (final resource in await db.getResourcesByType(resourceType)) {
        final id = resource.id?.toString();
        entries.add(
          fhir.BundleEntry(
            fullUrl: id != null
                ? '${resource.resourceTypeString}/$id'.toFhirUri
                : null,
            resource: resource,
          ),
        );
      }
    }
    return fhir.Bundle(
      type: fhir.BundleType.collection,
      total: entries.length.toFhirUnsignedInt,
      timestamp: DateTime.now().toUtc().toFhirInstant,
      entry: entries.isEmpty ? null : entries,
    );
  }

  /// Whether [payload] is one of our encrypted envelopes rather than a plain
  /// Bundle.
  ///
  /// Callers use it to decide whether to ask for a passphrase at all: a FHIR
  /// Bundle produced elsewhere restores without one.
  static bool isEncrypted(String payload) => BackupCrypto.isEnvelope(payload);

  /// Decrypts [payload] when it is an envelope, and returns the Bundle JSON.
  ///
  /// A plain Bundle passes through untouched: importing FHIR produced
  /// elsewhere is legitimate, and refusing it would not make anything safer
  /// since the caller already holds the data.
  ///
  /// Throws [BackupDecryptionException] on a wrong passphrase or tampered
  /// bytes, and [BackupPassphraseRequired] when an envelope arrives without
  /// one.
  static String decode(String payload, String? passphrase) {
    if (!BackupCrypto.isEnvelope(payload)) return payload;
    if (passphrase == null || passphrase.isEmpty) {
      throw const BackupPassphraseRequired(
        'This backup is encrypted and cannot be read without its passphrase',
      );
    }
    return BackupCrypto.decrypt(payload, passphrase);
  }

  /// Saves every resource in [payload], reporting what could not be taken.
  ///
  /// One transaction for the whole restore: each `saveResource` otherwise
  /// commits on its own, measured at 71.7ms per resource against 2.2ms inside
  /// a shared transaction, so a five-thousand-resource backup would take
  /// minutes rather than seconds. Restoring onto a replacement device is the
  /// recovery path the design rests on and cannot be something an operator
  /// waits out.
  ///
  /// Per-entry failures are collected rather than aborting. A restore reports
  /// what it could and could not take; all-or-nothing would turn one bad entry
  /// into no record at all.
  static Future<BackupRestoreResult> restore(
    FhirAntDb db,
    String payload, {
    String? passphrase,
  }) async {
    final content = decode(payload, passphrase);

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Invalid JSON: $e');
    }
    if (json['resourceType'] != 'Bundle') {
      throw FormatException('Expected a Bundle, got: ${json['resourceType']}');
    }

    final entries = fhir.Bundle.fromJson(json).entry ?? [];
    var saved = 0;
    final failures = <String>[];

    await db.transaction<void>(() async {
      for (final entry in entries) {
        final resource = entry.resource;
        if (resource == null) {
          failures.add('Bundle entry has no resource');
          continue;
        }
        try {
          if (await db.saveResource(resource)) {
            saved++;
          } else {
            failures.add(
              'Failed to save ${resource.resourceTypeString}/'
              '${resource.id ?? "(no id)"}',
            );
          }
        } catch (e) {
          failures.add(
            'Failed to save ${resource.resourceTypeString}/'
            '${resource.id ?? "(no id)"}: $e',
          );
        }
      }
    });

    return BackupRestoreResult(saved: saved, failures: failures);
  }
}

/// A passphrase was needed and not supplied.
///
/// An Exception rather than an ArgumentError: a caller omitting the passphrase
/// is an expected condition to report back, not a bug in the calling code.
class BackupPassphraseRequired implements Exception {
  const BackupPassphraseRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a restore took, and what it could not.
class BackupRestoreResult {
  const BackupRestoreResult({required this.saved, required this.failures});

  /// Resources written to the database.
  final int saved;

  /// One message per entry that could not be written.
  final List<String> failures;

  int get failed => failures.length;
}
