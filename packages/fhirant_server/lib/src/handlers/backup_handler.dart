import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
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
    final resourceTypes = await dbInterface.getResourceTypes();

    final entries = <fhir.BundleEntry>[];
    for (final resourceType in resourceTypes) {
      final resources = await dbInterface.getResourcesByType(resourceType);
      for (final resource in resources) {
        final typeString = resource.resourceTypeString;
        final id = resource.id?.toString();
        entries.add(
          fhir.BundleEntry(
            fullUrl: id != null ? '$typeString/$id'.toFhirUri : null,
            resource: resource,
          ),
        );
      }
    }

    final bundle = fhir.Bundle(
      type: fhir.BundleType.collection,
      total: entries.length.toFhirUnsignedInt,
      timestamp: DateTime.now().toUtc().toFhirInstant,
      entry: entries.isEmpty ? null : entries,
    );

    return Response.ok(
      BackupCrypto.encrypt(jsonEncode(bundle.toJson()), passphrase),
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

    // An encrypted envelope is decrypted first, then restored exactly as a
    // plain Bundle would be. A plain Bundle is still accepted: importing FHIR
    // produced elsewhere is a legitimate use, and refusing it would not make
    // anything safer — the caller already holds the data.
    var content = body;
    if (BackupCrypto.isEnvelope(body)) {
      final passphrase = _passphraseHeader(request);
      if (passphrase == null || passphrase.isEmpty) {
        return _outcome(
          400,
          fhir.IssueType.required_,
          'This backup is encrypted. Supply the passphrase it was created '
          'with in the X-Backup-Passphrase header.',
        );
      }
      try {
        content = BackupCrypto.decrypt(body, passphrase);
      } on BackupDecryptionException catch (e) {
        return _outcome(400, fhir.IssueType.security, e.message);
      }
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return Response(
        400,
        body: jsonEncode(
          fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.invalid,
                diagnostics: 'Invalid JSON: $e'.toFhirString,
              ),
            ],
          ).toJson(),
        ),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    final resourceType = json['resourceType'];
    if (resourceType != 'Bundle') {
      return Response(
        400,
        body: jsonEncode(
          fhir.OperationOutcome(
            issue: [
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.invalid,
                diagnostics:
                    'Expected a Bundle, got: $resourceType'.toFhirString,
              ),
            ],
          ).toJson(),
        ),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    final bundle = fhir.Bundle.fromJson(json);
    final bundleEntries = bundle.entry ?? [];

    var savedCount = 0;
    var errorCount = 0;
    final issues = <fhir.OperationOutcomeIssue>[];

    // One database transaction for the whole restore. Each saveResource
    // otherwise commits on its own — measured at 71.7ms per resource against
    // 2.2ms inside a shared transaction, so a five-thousand-resource backup
    // would take minutes rather than seconds. Restoring onto a replacement
    // device is the recovery path this whole design rests on; it cannot be
    // something an operator waits out.
    //
    // Per-entry failures are still caught and reported individually rather
    // than aborting: a restore reports what it could and could not take, and
    // an all-or-nothing import would turn one bad entry into no record at all.
    await dbInterface.transaction<void>(() async {
      for (final entry in bundleEntries) {
        final resource = entry.resource;
        if (resource == null) {
          errorCount++;
          issues.add(
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.warning,
              code: fhir.IssueType.incomplete,
              diagnostics: 'Bundle entry has no resource'.toFhirString,
            ),
          );
          continue;
        }

        try {
          final saved = await dbInterface.saveResource(resource);
          if (saved) {
            savedCount++;
          } else {
            errorCount++;
            issues.add(
              fhir.OperationOutcomeIssue(
                severity: fhir.IssueSeverity.error,
                code: fhir.IssueType.exception,
                diagnostics:
                    'Failed to save ${resource.resourceTypeString}/${resource.id}'
                        .toFhirString,
              ),
            );
          }
        } catch (e, stackTrace) {
          errorCount++;
          FhirantLogging().logError(
            'Error saving a ${resource.resourceTypeString} during restore',
            e,
            stackTrace,
          );
          issues.add(
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.exception,
              diagnostics:
                  'Error saving ${resource.resourceTypeString}/${resource.id}'
                      .toFhirString,
            ),
          );
        }
      }
    });

    // Always include a summary issue
    issues.insert(
      0,
      fhir.OperationOutcomeIssue(
        severity: errorCount > 0
            ? fhir.IssueSeverity.warning
            : fhir.IssueSeverity.information,
        code: fhir.IssueType.informational,
        diagnostics: 'Restore complete: $savedCount saved, $errorCount errors, '
                '${bundleEntries.length} total entries'
            .toFhirString,
      ),
    );

    final outcome = fhir.OperationOutcome(issue: issues);

    return Response.ok(
      jsonEncode(outcome.toJson()),
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
