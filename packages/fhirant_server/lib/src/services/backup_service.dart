import 'dart:convert';
import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:fhirant_server/src/utils/file_refusal.dart';
import 'package:fhirant_server/src/utils/spec_loader.dart'
    show isSpecResource, specTag;

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

  /// Every stored resource as an encrypted envelope, less the specification
  /// load (see [createFile]).
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

  /// The whole database as one SQLite file encrypted under [passphrase],
  /// written to [path] (which must not exist). See
  /// [FhirAntDb.copyEncrypted]: streamed by SQLite, so a 7 GB store is a
  /// matter of minutes and no memory, where [create]'s Bundle-in-JSON was
  /// measured at 51.8 s and 548 MB per 50 MB (REVIEW-2026-09-06 finding
  /// 33). The file restores with [restoreFile], or opens as a database.
  ///
  /// The specification load (the resources tagged [specTag], 4,212 of them,
  /// 48 MB) is left out of both backup formats: it ships with every install,
  /// and a restore into a fresh one reloads it from the bundle when it finds
  /// no CodeSystems (REVIEW §6.1, decided 2026-09-08).
  static Future<File> createFile(
    FhirAntDb db,
    String passphrase,
    String path,
  ) async {
    if (passphrase.isEmpty) {
      throw const BackupPassphraseRequired(
        'A backup cannot be created without a passphrase',
      );
    }
    await db.copyEncrypted(path, passphrase, withoutTag: specTag);
    return File(path);
  }

  /// Restores the file at [path]: an encrypted SQLite backup from
  /// [createFile], an encrypted Bundle envelope from [create], or a plain
  /// FHIR Bundle, told apart by the first byte (JSON starts with `{`; a
  /// SQLCipher file starts with its random salt).
  ///
  /// [withServerState] is [FhirAntDb.restoreEncrypted]'s: false brings in
  /// the FHIR record only. A Bundle carries nothing else in any case.
  ///
  /// With [scanner], every stored resource in the backup has its files
  /// checked and scanned ([fileRefusal]; OWASP ASVS 5.0.0 V5.4.3, "Verify
  /// that files obtained from untrusted sources are scanned by antivirus
  /// scanners", read in the ASVS 5.0.0 JSON release 2026-10-21) before
  /// anything is written. A resource refused is left out and listed in the
  /// result's failures; the rest restores. A scanner that cannot answer
  /// ends the restore with nothing written ([BackupScanUnavailable]). An
  /// encrypted backup's refused rows are deleted from the file at [path]
  /// (the server's is its own temporary copy of the upload). The app has
  /// no scanner and passes none.
  static Future<BackupRestoreResult> restoreFile(
    FhirAntDb db,
    String path, {
    String? passphrase,
    bool withServerState = true,
    FileScanner? scanner,
  }) async {
    if (await isJsonFile(path)) {
      return restore(
        db,
        await File(path).readAsString(),
        passphrase: passphrase,
        scanner: scanner,
      );
    }
    if (passphrase == null || passphrase.isEmpty) {
      throw const BackupPassphraseRequired(
        'This backup is encrypted and cannot be read without its passphrase',
      );
    }
    final failures = <String>[];
    try {
      final restored = await db.restoreEncrypted(
        path,
        passphrase,
        withServerState: withServerState,
        admit: scanner == null
            ? null
            : (table, json) async {
                final fhir.Resource resource;
                try {
                  resource = fhir.Resource.fromJsonString(json);
                } catch (e) {
                  // Never restored unscanned: a row that does not parse
                  // cannot have its files found.
                  failures.add('Left out a $table row that is not a '
                      'readable resource: $e');
                  return false;
                }
                final why = await _refusal(scanner, resource);
                if (why == null) return true;
                failures.add('Left out ${_key(resource)} ($table): $why');
                return false;
              },
      );
      return BackupRestoreResult(saved: restored, failures: failures);
    } on BackupUnreadable catch (e) {
      throw BackupDecryptionException(e.toString());
    }
  }

  /// Whether the file at [path] is one of our encrypted Bundle envelopes,
  /// read from its first 4 KB: the envelope is written with `fhirantBackup`
  /// as its first key. The app used to read the whole file into a String
  /// to ask [isEncrypted] (REVIEW-2026-09-08 row 42).
  static Future<bool> isEncryptedFile(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    final bytes = <int>[];
    await file.openRead(0, 4096).forEach(bytes.addAll);
    final head = utf8.decode(bytes, allowMalformed: true);
    return RegExp(r'^\s*\{\s*"fhirantBackup"\s*:').hasMatch(head);
  }

  /// Whether the file is JSON, a Bundle or an envelope, rather than an
  /// encrypted database: its first 64 bytes are UTF-8 text whose first
  /// non-blank character is `{`.
  ///
  /// This used to look at the first non-blank byte alone. An encrypted
  /// backup starts with SQLCipher's random 16-byte salt, so one backup in
  /// 256 began with `{`, was read as a UTF-8 string and failed with a
  /// FileSystemException instead of the wrong-passphrase answer (seen once
  /// in a suite run, 2026-09-18, `tool/review_2026-09-17/fix_q6/`). Sixty
  /// four random bytes that are also valid UTF-8 are not a chance worth
  /// naming. Malformed JSON (`{not-json`) is still JSON here, so it is
  /// reported as invalid JSON and not as a backup missing its passphrase.
  static Future<bool> isJsonFile(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    final bytes = await file.openRead(0, 64).first;
    // A multi-byte character cut by the 64-byte window is not malformed
    // UTF-8, so up to three trailing bytes may be dropped before deciding.
    String? head;
    for (var drop = 0; drop <= 3 && drop < bytes.length; drop++) {
      try {
        head = utf8.decode(bytes.sublist(0, bytes.length - drop));
        break;
      } on FormatException {
        continue;
      }
    }
    if (head == null) return false;
    return RegExp(r'^\s*\{').hasMatch(head);
  }

  /// Every stored resource as a collection Bundle, unencrypted.
  ///
  /// Exposed for the handler, which reports the entry count, and for tests.
  /// Callers that write this anywhere are responsible for protecting it.
  static Future<fhir.Bundle> bundle(FhirAntDb db) async {
    final entries = <fhir.BundleEntry>[];
    for (final resourceType in await db.getResourceTypes()) {
      for (final resource in await db.getResourcesByType(resourceType)) {
        if (isSpecResource(resource)) continue;
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
  ///
  /// With [scanner], each entry's files are checked and scanned before the
  /// transaction opens (a scan is a network round trip, and the store has
  /// one connection); see [restoreFile].
  static Future<BackupRestoreResult> restore(
    FhirAntDb db,
    String payload, {
    String? passphrase,
    FileScanner? scanner,
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
    final refused = <fhir.BundleEntry>{};
    if (scanner != null) {
      for (final entry in entries) {
        final resource = entry.resource;
        if (resource == null) continue;
        final why = await _refusal(scanner, resource);
        if (why == null) continue;
        refused.add(entry);
        failures.add('Left out ${_key(resource)}: $why');
      }
    }

    await db.transaction<void>(() async {
      for (final entry in entries) {
        if (refused.contains(entry)) continue;
        final resource = entry.resource;
        if (resource == null) {
          failures.add('Bundle entry has no resource');
          continue;
        }
        try {
          // Per-resource: the rest of the backup still restores, and the
          // caller gets the list with each cause. The wrapper used to
          // swallow the cause and return null (REVIEW-2026-09-17 ST7).
          await db.saveResource(resource);
          saved++;
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

/// Why [resource]'s files keep it out of a restore, or null when they do
/// not. Throws [BackupScanUnavailable] when the scanner cannot answer: the
/// file would otherwise be restored unscanned.
Future<String?> _refusal(FileScanner scanner, fhir.Resource resource) async {
  final refusal = await fileRefusal(scanner, resource);
  if (refusal == null) return null;
  if (refusal.code == fhir.IssueType.transient) {
    throw BackupScanUnavailable(refusal.message);
  }
  return refusal.message;
}

String _key(fhir.Resource resource) =>
    '${resource.resourceTypeString}/${resource.id ?? "(no id)"}';

/// The scanner could not answer for a file in a backup, so nothing was
/// restored.
class BackupScanUnavailable implements Exception {
  const BackupScanUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
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
