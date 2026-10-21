import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/services/file_scanner.dart';
import 'package:fhirant_server/src/utils/file_data.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:shelf/shelf.dart';

/// Why a resource's files keep it out of the store: the status, issue code
/// and diagnostics of the reply.
typedef FileRefusal = ({int status, fhir.IssueType code, String message});

/// Scans every file in [resource] (OWASP ASVS 5.0.0 V5.4.3), and says why it
/// may not be stored, or `null` when it may.
///
/// - A match is 422 `business-rule`. R4B http.html, create (read
///   2026-10-21): "When the server rejects the content of the resource
///   because of business rules ... the server returns a 422 Unprocessable
///   Entity".
/// - No answer from the scanner is 503 `transient`: the file is refused,
///   never stored unscanned (Grey, 2026-10-21: refusing is fair when the
///   file could be malignant). http.html allows a 5xx here: "servers may
///   also return 5xx errors in these cases without being deemed
///   non-conformant". The issue type's definition: "The system receiving
///   the message may be able to resubmit the same content once an
///   underlying issue is resolved."
/// - With no [scanner] (the phone, or a server started without one) nothing
///   is scanned, as before.
///
/// Call it before a database transaction opens where the stored resource is
/// already known: a scan is a network round trip, and the store has one
/// connection.
Future<FileRefusal?> fileRefusal(
  FileScanner? scanner,
  fhir.Resource resource,
) async {
  if (scanner == null) return null;
  for (final file in fileData(resource)) {
    final bytes = file.bytes;
    if (bytes == null) {
      return (
        status: 400,
        code: fhir.IssueType.invalid,
        message: '${file.path} is not base64',
      );
    }
    final ScanResult result;
    try {
      result = await scanner.scan(bytes);
    } on ScannerUnavailable catch (e) {
      // The scanner's address stays in the log, out of the reply.
      FhirantLogging().logError('File scan failed for ${file.path}', e);
      return (
        status: 503,
        code: fhir.IssueType.transient,
        message: 'The file at ${file.path} could not be scanned for malware, '
            'so it was not stored; try again later',
      );
    }
    if (result is ScanFound) {
      FhirantLogging().logWarning(
        'Refused ${file.path}: malware signature ${result.signature}',
      );
      return (
        status: 422,
        code: fhir.IssueType.businessRule,
        message: 'The file at ${file.path} matched the malware signature '
            '${result.signature}; it was not stored',
      );
    }
  }
  return null;
}

/// [refusal] as the reply to a REST interaction.
Response fileRefusalResponse(FileRefusal refusal) =>
    outcome(refusal.status, refusal.code, refusal.message);
