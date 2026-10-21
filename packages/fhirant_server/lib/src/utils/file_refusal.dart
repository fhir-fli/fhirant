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
        'Refused ${file.path}: scanner signature ${result.signature}',
      );
      return (
        status: 422,
        code: fhir.IssueType.businessRule,
        message: _foundMessage(file.path, result.signature),
      );
    }
  }
  return null;
}

/// Why [signature] keeps the file at [path] out, in words the person who
/// sent it can act on.
///
/// Two of clamd's heuristics are not malware but a file clamd could not
/// read through, and say so in their names (measured on
/// clamav/clamav:1.5.4, tool/review_2026-10-17/clamd/encrypted_samples.tsv
/// and libclamav/others.c):
/// - `Heuristics.Encrypted.*` (AlertEncrypted, in clamav/clamd.conf): a
///   password-protected zip, PDF or Office file. Refused, as the NHS
///   e-Referral Service refuses a file that "could be password protected
///   ... so scanning could not be performed" (Changes to file attachments
///   in the NHS e-Referral Service, read 2026-10-21), and as Medplum serves
///   only Binaries GuardDuty marked NO_THREATS_FOUND (medplum
///   docs/api/fhir/operations/binary-scan.md, read 2026-10-21).
/// - `Heuristics.Limits.Exceeded.*` (AlertExceedsMax): a scan clamd cut
///   short at one of its limits.
String _foundMessage(String path, String signature) {
  if (signature.startsWith('Heuristics.Encrypted.')) {
    return 'The file at $path is password-protected or encrypted, so it '
        'could not be scanned for malware, and it was not stored. Send it '
        'without the password ($signature)';
  }
  if (signature.startsWith('Heuristics.Limits.Exceeded.')) {
    return 'The file at $path is too large or too deeply nested to be '
        'scanned for malware, so it could not be scanned whole, and it was '
        'not stored ($signature)';
  }
  return 'The file at $path matched the malware signature $signature; it '
      'was not stored';
}

/// [refusal] as the reply to a REST interaction.
Response fileRefusalResponse(FileRefusal refusal) =>
    outcome(refusal.status, refusal.code, refusal.message);
