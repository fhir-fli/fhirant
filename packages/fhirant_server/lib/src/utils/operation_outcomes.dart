import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:shelf/shelf.dart';

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
