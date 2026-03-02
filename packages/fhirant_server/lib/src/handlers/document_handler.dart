// ignore_for_file: lines_longer_than_80_chars
import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_logging/fhirant_logging.dart';
import 'package:shelf/shelf.dart';

/// Handler for `GET /Composition/<id>/$document`.
///
/// Generates a FHIR document Bundle (type=document) from a Composition
/// resource by following all references and collecting them into a single
/// self-contained bundle.
///
/// Per the FHIR spec, the first entry is always the Composition itself,
/// followed by the subject, then all other referenced resources.
Future<Response> documentHandler(
  Request request,
  String id,
  FhirAntDb dbInterface,
) async {
  try {
    // 1. Fetch the Composition
    final composition = await dbInterface.getResource(
      fhir.R4ResourceType.Composition,
      id,
    );
    if (composition == null) {
      return _operationOutcome(404, 'Composition/$id not found');
    }

    if (composition is! fhir.Composition) {
      return _operationOutcome(
        500,
        'Resource Composition/$id is not a valid Composition',
      );
    }

    // 2. Collect all references from the Composition
    final references = <String>{};
    _collectCompositionReferences(composition, references);

    // 3. Resolve all references to actual resources
    final resolvedResources = <fhir.Resource>[];
    fhir.Resource? subjectResource;

    for (final ref in references) {
      final resolved = _parseAndFetchReference(ref, dbInterface);
      final resource = await resolved;
      if (resource != null) {
        // Track subject separately so it can be placed second
        if (composition.subject?.reference?.valueString == ref) {
          subjectResource = resource;
        } else {
          resolvedResources.add(resource);
        }
      }
    }

    // 4. Build document Bundle
    // Order: Composition first, then subject, then all others
    final baseUrl = _baseUrl(request);
    final entries = <fhir.BundleEntry>[];

    // First entry: Composition
    entries.add(_bundleEntry(composition, baseUrl));

    // Second entry: subject (if present)
    if (subjectResource != null) {
      entries.add(_bundleEntry(subjectResource, baseUrl));
    }

    // Remaining entries: all other referenced resources
    for (final resource in resolvedResources) {
      entries.add(_bundleEntry(resource, baseUrl));
    }

    final bundle = fhir.Bundle(
      type: fhir.BundleType.document,
      timestamp: DateTime.now().toFhirInstant,
      entry: entries,
    );

    FhirantLogging().logInfo(
      '\$document for Composition/$id returned ${entries.length} entries',
    );

    return Response.ok(
      bundle.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, stackTrace) {
    FhirantLogging().logError(
      'Error in \$document for Composition/$id',
      e,
      stackTrace,
    );
    return _operationOutcome(500, 'Internal error: $e');
  }
}

/// Collect all Reference strings from a Composition.
void _collectCompositionReferences(
  fhir.Composition composition,
  Set<String> references,
) {
  void addRef(fhir.Reference? ref) {
    final refString = ref?.reference?.valueString;
    if (refString != null && refString.contains('/')) {
      references.add(refString);
    }
  }

  void addRefs(List<fhir.Reference>? refs) {
    if (refs != null) {
      for (final ref in refs) {
        addRef(ref);
      }
    }
  }

  // Top-level references
  addRef(composition.subject);
  addRef(composition.encounter);
  addRefs(composition.author);
  addRef(composition.custodian);

  // Attester parties
  if (composition.attester != null) {
    for (final attester in composition.attester!) {
      addRef(attester.party);
    }
  }

  // Event detail references
  if (composition.event != null) {
    for (final event in composition.event!) {
      addRefs(event.detail);
    }
  }

  // RelatesTo target references
  if (composition.relatesTo != null) {
    for (final relatesTo in composition.relatesTo!) {
      final targetRef = relatesTo.targetX.isAs<fhir.Reference>();
      addRef(targetRef);
    }
  }

  // Section references (recursive)
  if (composition.section != null) {
    for (final section in composition.section!) {
      _collectSectionReferences(section, references);
    }
  }
}

/// Recursively collect references from a CompositionSection.
void _collectSectionReferences(
  fhir.CompositionSection section,
  Set<String> references,
) {
  void addRef(fhir.Reference? ref) {
    final refString = ref?.reference?.valueString;
    if (refString != null && refString.contains('/')) {
      references.add(refString);
    }
  }

  void addRefs(List<fhir.Reference>? refs) {
    if (refs != null) {
      for (final ref in refs) {
        addRef(ref);
      }
    }
  }

  addRefs(section.author);
  addRef(section.focus);
  addRefs(section.entry);

  // Recurse into nested sections
  if (section.section != null) {
    for (final nested in section.section!) {
      _collectSectionReferences(nested, references);
    }
  }
}

/// Parse a FHIR reference string (e.g., "Patient/123") and fetch the resource.
Future<fhir.Resource?> _parseAndFetchReference(
  String reference,
  FhirAntDb dbInterface,
) async {
  final parts = reference.split('/');
  if (parts.length != 2) return null;

  final resourceType = fhir.R4ResourceType.fromString(parts[0]);
  if (resourceType == null) return null;

  return dbInterface.getResource(resourceType, parts[1]);
}

/// Build a BundleEntry with fullUrl.
fhir.BundleEntry _bundleEntry(fhir.Resource resource, String baseUrl) {
  final resType = resource.resourceTypeString;
  final resId = resource.id?.toString() ?? '';
  return fhir.BundleEntry(
    resource: resource,
    fullUrl:
        resId.isNotEmpty ? fhir.FhirUri('$baseUrl/$resType/$resId') : null,
  );
}

/// Extracts the base URL from a request.
String _baseUrl(Request request) {
  final uri = request.requestedUri;
  return uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
}

/// Returns an OperationOutcome response.
Response _operationOutcome(int statusCode, String message) {
  final outcome = fhir.OperationOutcome(
    issue: [
      fhir.OperationOutcomeIssue(
        severity: statusCode >= 500
            ? fhir.IssueSeverity.fatal
            : fhir.IssueSeverity.error,
        code: statusCode == 404
            ? fhir.IssueType.notFound
            : fhir.IssueType.processing,
        diagnostics: message.toFhirString,
      ),
    ],
  );
  return Response(
    statusCode,
    body: outcome.toJsonString(),
    headers: {'Content-Type': 'application/json'},
  );
}
