import 'dart:convert';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for POST /$backup — exports all FHIR resources as a collection
/// Bundle.
Future<Response> backupHandler(
  Request request,
  FhirAntDb dbInterface,
) async {
  try {
    final resourceTypes = await dbInterface.getResourceTypes();

    final entries = <fhir.BundleEntry>[];
    for (final resourceType in resourceTypes) {
      final resources = await dbInterface.getResourcesByType(resourceType);
      for (final resource in resources) {
        final typeString = resource.resourceTypeString;
        final id = resource.id?.toString();
        entries.add(fhir.BundleEntry(
          fullUrl: id != null ? '$typeString/$id'.toFhirUri : null,
          resource: resource,
        ));
      }
    }

    final bundle = fhir.Bundle(
      type: fhir.BundleType.collection,
      total: entries.length.toFhirUnsignedInt,
      timestamp: DateTime.now().toUtc().toFhirInstant,
      entry: entries.isEmpty ? null : entries,
    );

    return Response.ok(
      jsonEncode(bundle.toJson()),
      headers: {'content-type': 'application/fhir+json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError('Backup failed', e, stackTrace);
    final outcome = fhir.OperationOutcome(
      issue: [
        fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: fhir.IssueType.exception,
          diagnostics: 'Backup failed: $e'.toFhirString,
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
      return Response(400,
        body: jsonEncode(fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.invalid,
              diagnostics: 'Request body is empty'.toFhirString,
            ),
          ],
        ).toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return Response(400,
        body: jsonEncode(fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.invalid,
              diagnostics: 'Invalid JSON: $e'.toFhirString,
            ),
          ],
        ).toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    final resourceType = json['resourceType'];
    if (resourceType != 'Bundle') {
      return Response(400,
        body: jsonEncode(fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.error,
              code: fhir.IssueType.invalid,
              diagnostics:
                  'Expected a Bundle, got: $resourceType'.toFhirString,
            ),
          ],
        ).toJson()),
        headers: {'content-type': 'application/fhir+json'},
      );
    }

    final bundle = fhir.Bundle.fromJson(json);
    final bundleEntries = bundle.entry ?? [];

    int savedCount = 0;
    int errorCount = 0;
    final issues = <fhir.OperationOutcomeIssue>[];

    for (final entry in bundleEntries) {
      final resource = entry.resource;
      if (resource == null) {
        errorCount++;
        issues.add(fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.warning,
          code: fhir.IssueType.incomplete,
          diagnostics: 'Bundle entry has no resource'.toFhirString,
        ));
        continue;
      }

      try {
        final saved = await dbInterface.saveResource(resource);
        if (saved) {
          savedCount++;
        } else {
          errorCount++;
          issues.add(fhir.OperationOutcomeIssue(
            severity: fhir.IssueSeverity.error,
            code: fhir.IssueType.exception,
            diagnostics:
                'Failed to save ${resource.resourceTypeString}/${resource.id}'
                    .toFhirString,
          ));
        }
      } catch (e) {
        errorCount++;
        issues.add(fhir.OperationOutcomeIssue(
          severity: fhir.IssueSeverity.error,
          code: fhir.IssueType.exception,
          diagnostics:
              'Error saving ${resource.resourceTypeString}/${resource.id}: $e'
                  .toFhirString,
        ));
      }
    }

    // Always include a summary issue
    issues.insert(
      0,
      fhir.OperationOutcomeIssue(
        severity: errorCount > 0
            ? fhir.IssueSeverity.warning
            : fhir.IssueSeverity.information,
        code: fhir.IssueType.informational,
        diagnostics:
            'Restore complete: $savedCount saved, $errorCount errors, '
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
          diagnostics: 'Restore failed: $e'.toFhirString,
        ),
      ],
    );
    return Response.internalServerError(
      body: jsonEncode(outcome.toJson()),
      headers: {'content-type': 'application/fhir+json'},
    );
  }
}
