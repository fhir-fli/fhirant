import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart' show InvalidSearchParameter;
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// 400 with an OperationOutcome, for a SearchParameter the store cannot
/// index by (fhir_db refuses it at save: no code, base or expression, a
/// type it has no table for, an unknown base, a code the specification
/// defines on that base, or an expression that does not parse).
Response invalidSearchParameter(InvalidSearchParameter e) => Response(
      400,
      body: fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.invalid,
            diagnostics: e.message.toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/fhir+json'},
    );

/// The 404 of a FHIR interaction, as an OperationOutcome.
///
/// R4B http.html (read 2026-09-08): a read of an unknown resource returns
/// "a 404 Not Found error, with an operation outcome explaining" it. Read,
/// vread, history, PATCH and `$meta` used to answer `{"error": "Resource not
/// found"}` (REVIEW-2026-09-08 row 27).
Response notFoundOutcome(String what) => Response(
      404,
      body: fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.notFound,
            diagnostics: '$what not found'.toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/fhir+json'},
    );

/// The 400 for a path segment that names no R4 resource type, as an
/// OperationOutcome.
Response invalidTypeOutcome(String resourceType) => Response(
      400,
      body: fhir.OperationOutcome(
        issue: [
          fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.invalid,
            diagnostics: 'Invalid resource type: $resourceType'.toFhirString,
          ),
        ],
      ).toJsonString(),
      headers: {'Content-Type': 'application/fhir+json'},
    );

/// The one error reply: [status], one OperationOutcome issue of [code] with
/// [diagnostics], severity `error`, labelled `application/fhir+json` (R4B
/// http.html, read whole 2026-09-22, verbatim: "The correct mime type SHALL
/// be used by clients and servers"). A 5xx is also logged, with the
/// diagnostics, so a server-side failure never leaves without a line.
///
/// Before 2026-09-22 this was written as 14 private helpers of six shapes
/// across 12 handler files and 15 inline maps: some labelled
/// `application/json`, some built the FHIR class and some a map, some
/// marked a 5xx `fatal`, five logged every 4xx as a warning.
Response outcome(
  int status,
  fhir.IssueType code,
  String diagnostics, {
  Map<String, Object>? context,
}) {
  if (status >= 500) {
    FhirantLogging().logError('$status ${code.valueString}: $diagnostics');
  }
  return Response(
    status,
    body: fhir.OperationOutcome(
      issue: [
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: code,
          diagnostics: diagnostics.toFhirString,
        ),
      ],
    ).toJsonString(),
    headers: {'Content-Type': 'application/fhir+json'},
    context: context,
  );
}

/// [outcome] for a request the server could not process: issue code
/// `exception`, diagnostics `"[message]: [details]"`, 500 unless given.
Response exceptionOutcome(
  String message,
  String details, {
  int statusCode = 500,
  Map<String, Object>? context,
}) =>
    outcome(
      statusCode,
      fhir.IssueType.exception,
      '$message: $details',
      context: context,
    );

/// [outcome] for a request the server refuses as malformed: 400, issue code
/// `processing`.
Response validationOutcome(String message) =>
    outcome(400, fhir.IssueType.processing, message);

/// The [fhir.IssueType] for a code string such as `not-found`, as the store's
/// refusals carry it (`ValueSetRefusal.issueCode`).
fhir.IssueType issueTypeOfCode(String code) =>
    fhir.IssueType.fromJson({'value': code});
