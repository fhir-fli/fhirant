import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart' show InvalidSearchParameter;
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
