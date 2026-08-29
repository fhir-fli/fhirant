import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/backup_service.dart';
import 'package:fhirant_server/src/utils/backup_crypto.dart';
import 'package:shelf/shelf.dart';

/// Handler for POST /$backup — exports all FHIR resources as a collection
/// Bundle, encrypted under a passphrase the caller supplies.
///
/// The passphrase is required. A backup is the copy of the record that leaves
/// the device — onto a second phone, or an SD card — and it cannot inherit the
/// database's own encryption, whose key is sealed in platform secure storage
/// and therefore cannot travel with it. An unencrypted export would undo the
/// at-rest protection at exactly the moment the record is most exposed.
///
/// Supply it in the request body as a Parameters resource:
/// `{"resourceType":"Parameters","parameter":[{"name":"passphrase",
/// "valueString":"…"}]}`. In the body rather than the query string on purpose
/// — request URIs are written to the server log.
Future<Response> backupHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final passphrase = await _readPassphrase(request);
    if (passphrase == null || passphrase.isEmpty) {
      return _outcome(
        400,
        fhir.IssueType.required_,
        'A passphrase is required. Send a Parameters resource with a '
        'passphrase parameter; the backup is encrypted with it, and it is '
        'the only thing that can decrypt it.',
      );
    }
    return Response.ok(
      await BackupService.create(dbInterface, passphrase),
      headers: {'content-type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Backup failed', e, stackTrace);
    final outcome = fhir.OperationOutcome(
      issue: [
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: fhir.IssueType.exception,
          diagnostics: 'Backup failed'.toFhirString,
        ),
      ],
    );
    return Response.internalServerError(
      body: jsonEncode(outcome.toJson()),
      headers: {'content-type': 'application/fhir+json'},
    );
  }
}

/// Handler for POST /$restore — imports resources from a FHIR Bundle.
///
/// Accepts a Bundle (type: collection or transaction) and upserts each
/// entry's resource into the database.
Future<Response> restoreHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final body = await request.readAsString();
    if (body.isEmpty) {
      return Response(
        400,
        body: jsonEncode(
          fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.invalid,
                diagnostics: 'Request body is empty'.toFhirString,
              ),
            ],
          ).toJson(),
        ),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    // The app performs this same operation in process, so the work lives in
    // BackupService and this handler is the HTTP shape around it.
    final BackupRestoreResult result;
    try {
      result = await BackupService.restore(
        dbInterface,
        body,
        passphrase: _passphraseHeader(request),
      );
    } on BackupPassphraseRequired {
      return _outcome(
        400,
        fhir.IssueType.required_,
        'This backup is encrypted. Supply the passphrase it was created '
        'with in the X-Backup-Passphrase header.',
      );
    } on BackupDecryptionException catch (e) {
      return _outcome(400, fhir.IssueType.security, e.message);
    } on FormatException catch (e) {
      return _outcome(400, fhir.IssueType.invalid, e.message);
    }

    // The summary issue comes first, so a caller reading only the first issue
    // still learns whether the restore took everything.
    final issues = <fhir.OperationOutcomeIssue>[
      fhir.OperationOutcomeIssue(
        severity: result.failed > 0
            ? fhir.IssueSeverity.warning
            : fhir.IssueSeverity.information,
        code: fhir.IssueType.informational,
        diagnostics:
            'Restore complete: ${result.saved} saved, ${result.failed} errors, '
                    '${result.saved + result.failed} total entries'
                .toFhirString,
      ),
      for (final message in result.failures)
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: fhir.IssueType.exception,
          diagnostics: message.toFhirString,
        ),
    ];

    return Response.ok(
      jsonEncode(fhir.OperationOutcome(issue: issues).toJson()),
      headers: {'content-type': 'application/fhir+json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Restore failed', e, stackTrace);
    final outcome = fhir.OperationOutcome(
      issue: [
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: fhir.IssueType.exception,
          diagnostics: 'Restore failed'.toFhirString,
        ),
      ],
    );
    return Response.internalServerError(
      body: jsonEncode(outcome.toJson()),
      headers: {'content-type': 'application/fhir+json'},
    );
  }
}

/// Reads the `passphrase` parameter from a Parameters body.
///
/// Returns null when the body is absent, unparseable, or carries no such
/// parameter — the caller turns all of those into the same "passphrase
/// required" answer, so a malformed body cannot be mistaken for consent to an
/// unencrypted export.
Future<String?> _readPassphrase(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) return null;

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }

  final parameters = json['parameter'];
  if (parameters is! List) return null;
  for (final entry in parameters) {
    if (entry is Map && entry['name'] == 'passphrase') {
      final value = entry['valueString'];
      if (value is String) return value;
    }
  }
  return null;
}

Response _outcome(int status, fhir.IssueType code, String diagnostics) {
  return Response(
    status,
    body: jsonEncode(
      fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: code,
            diagnostics: diagnostics.toFhirString,
          ),
        ],
      ).toJson(),
    ),
    headers: {'content-type': 'application/fhir+json'},
  );
}

/// Reads the restore passphrase from the `X-Backup-Passphrase` header.
///
/// A header rather than the body, because the body is the backup file itself;
/// and not the query string, because request URIs are written to the log.
String? _passphraseHeader(Request request) =>
    request.headers['x-backup-passphrase'];
