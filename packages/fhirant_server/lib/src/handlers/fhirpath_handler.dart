import 'dart:convert';
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhir_r4_path/fhir_r4_path.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:fhirant_server/src/utils/program_sandbox.dart';
import 'package:fhirant_server/src/utils/stored_resource.dart';
import 'package:fhirant_server/src/utils/operation_outcomes.dart';
import 'package:shelf/shelf.dart';

/// Shared FHIRPath engine — created once (creation is async and non-trivial)
/// and reused across requests.
Future<FHIRPathEngine>? _fhirPathEngineFuture;

Future<FHIRPathEngine> get _fhirPathEngine =>
    _fhirPathEngineFuture ??= FHIRPathEngine.create(WorkerContext());

/// FHIRPath Handler - Evaluate FHIRPath expressions against resources
Future<Response> fhirPathHandler(
  Request request,
  FhirAntDb dbInterface, {
  Duration deadline = kProgramDeadline,
}) async {
  try {
    FhirantLogging().logInfo('Received FHIRPath request');

    final queryParams = request.url.queryParameters;
    final expression = queryParams['expression'];
    final resourceType = queryParams['resourceType'];
    final resourceId = queryParams['resourceId'];

    if (expression == null || expression.isEmpty) {
      return outcome(400, fhir.IssueType.invalid,
          'Missing required parameter: expression');
    }

    fhir.Resource? resource;
    String? auditedEntity;

    // Try to get resource from query parameters first
    if (resourceType != null && resourceId != null) {
      // A user- or system-context scope is required for $fhirpath
      // (request_authorization.dart), so no patient compartment applies.
      final lookup =
          await lookupStored(request, dbInterface, resourceType, resourceId);
      if (lookup is! StoredFound) return lookupRefusal(lookup);
      resource = lookup.resource;
      // The audit middleware sees only `/$fhirpath` in the path, so it cannot
      // tell which record this disclosed. Hand the identity back up through
      // the response context, which is shelf's route for handler-to-middleware
      // data. Only the database read is declared: a resource posted in the
      // body came from the caller and was never disclosed by the server.
      auditedEntity = '$resourceType/$resourceId';
    } else {
      // Try to get resource from request body
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        try {
          resource = fhir.Resource.fromJsonString(body);
        } catch (e) {
          return outcome(400, fhir.IssueType.invalid,
              'Invalid resource in request body: $e');
        }
      }
    }

    if (resource == null) {
      return outcome(
          400,
          fhir.IssueType.invalid,
          'No resource provided. Use query params '
          '(resourceType & resourceId) or request body');
    }

    // Evaluate the FHIRPath expression. An expression that does not parse
    // is the client's error (400), not the server's (it used to be a 500;
    // REVIEW-2026-09-08 row 32).
    final engine = await _fhirPathEngine;
    try {
      engine.parse(expression);
    } catch (e) {
      return outcome(400, fhir.IssueType.invalid,
          'The FHIRPath expression does not parse: $e');
    }
    // Evaluated in a worker isolate under the deadline (REVIEW-2026-09-17
    // A9): the worker parses again from the text, builds its own engine,
    // and hands back JSON.
    final resourceJson = resource.toJson();
    final List<Object?> resultJson;
    try {
      resultJson = await runProgram(
        () async {
          final worker = await FHIRPathEngine.create(WorkerContext());
          final results = await worker.evaluate(
            fhir.Resource.fromJson(resourceJson),
            worker.parse(expression),
          );
          return [for (final e in results) (e as fhir.FhirBase).toJson()];
        },
        deadline: deadline,
      );
    } on ProgramTimeout catch (e) {
      return _tooCostly('$e');
    } on ProgramFailed catch (e) {
      return outcome(400, fhir.IssueType.invalid,
          'The FHIRPath expression failed: ${e.error}');
    }

    FhirantLogging().logInfo(
      'FHIRPath expression evaluated successfully',
    );

    return Response.ok(
      jsonEncode(resultJson),
      headers: {'Content-Type': 'application/json'},
      context: {
        if (auditedEntity != null) 'audit_entity': auditedEntity,
      },
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('FHIRPath evaluation failed', e, stackTrace);
    return outcome(500, fhir.IssueType.exception, 'FHIRPath evaluation error');
  }
}

/// 422 `too-costly`: the program was stopped at its deadline.
Response _tooCostly(String diagnostics) =>
    outcome(422, fhir.IssueType.tooCostly, diagnostics);
