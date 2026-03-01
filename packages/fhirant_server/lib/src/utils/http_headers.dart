import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;
import 'package:shelf/shelf.dart';

/// Utility for FHIR HTTP headers: ETag, Last-Modified, conditional operations.
class FhirHttpHeaders {
  /// Generate a weak ETag from the resource's version ID.
  static String etag(fhir.Resource resource) {
    final versionId = resource.meta?.versionId?.valueString ?? '1';
    return 'W/"$versionId"';
  }

  /// Parse a version string from an ETag header value.
  ///
  /// Accepts both weak (`W/"ver"`) and strong (`"ver"`) ETags.
  /// Returns `null` if the header is null or cannot be parsed.
  static String? parseETag(String? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(r'(?:W/)?"([^"]+)"').firstMatch(header);
    return match?.group(1);
  }

  /// Build standard FHIR resource response headers:
  /// Content-Type, ETag, and Last-Modified.
  static Map<String, String> resourceHeaders(fhir.Resource resource) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'ETag': etag(resource),
    };

    final lastUpdated = resource.meta?.lastUpdated?.valueDateTime;
    if (lastUpdated != null) {
      headers['Last-Modified'] = HttpDate.format(lastUpdated);
    }

    return headers;
  }

  /// Parse the Prefer header's return preference.
  /// Returns 'representation' (default), 'minimal', or 'OperationOutcome'.
  static String parsePreferReturn(Map<String, String> headers) {
    final prefer = headers['prefer'] ?? '';
    if (prefer.contains('return=minimal')) return 'minimal';
    if (prefer.contains('return=OperationOutcome')) return 'OperationOutcome';
    return 'representation';
  }

  /// Parse the Prefer header's handling preference.
  /// Returns 'lenient' (default) or 'strict'.
  /// When 'strict', the server should return 400 for unrecognized search params.
  /// When 'lenient', unrecognized params are silently ignored.
  static String parsePreferHandling(Map<String, String> headers) {
    final prefer = headers['prefer'] ?? '';
    if (prefer.contains('handling=strict')) return 'strict';
    return 'lenient';
  }

  /// Build the appropriate response based on Prefer header.
  static Response preferredResponse({
    required int statusCode,
    required fhir.Resource resource,
    required Map<String, String> headers,
    required String preference,
  }) {
    switch (preference) {
      case 'minimal':
        return Response(statusCode, headers: headers);
      case 'OperationOutcome':
        final oo = fhir.OperationOutcome(
          issue: [
            fhir.OperationOutcomeIssue(
              severity: fhir.IssueSeverity.information,
              code: fhir.IssueType.informational,
              diagnostics:
                  'Resource ${statusCode == 201 ? "created" : "updated"} successfully'
                      .toFhirString,
            ),
          ],
        );
        return Response(statusCode, body: oo.toJsonString(), headers: headers);
      default: // 'representation'
        return Response(statusCode,
            body: resource.toJsonString(), headers: headers);
    }
  }
}
