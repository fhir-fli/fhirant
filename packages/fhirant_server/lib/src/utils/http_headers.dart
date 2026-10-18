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
    if (header == null || header.trim().isEmpty) return null;
    final value = header.trim();
    // RFC 9110 13.1.1 (rfc-editor.org/rfc/rfc9110.txt, read 2026-10-18,
    // verbatim): "If the field value is "*", the condition is true if the
    // origin server has a current representation for the target resource";
    // "If the field value is a list of entity tags, the condition is true if
    // any of the listed tags match"; "Otherwise, the condition is false."
    if (value == '*') return null;
    // One or more entity tags, `W/"v"` or `"v"`, comma-separated. A list is
    // compared by its first tag (a limit of this server: the store takes
    // one version).
    final tag = RegExp('(?:W/)?"([^"]*)"');
    final list = RegExp(r'^(?:W/)?"[^"]*"(?:\s*,\s*(?:W/)?"[^"]*")*$');
    if (list.hasMatch(value)) return tag.firstMatch(value)!.group(1);
    // A header that names no version matches none: R4B http.html 3.1.0.5,
    // "If the version id given in the If-Match header does not match, the
    // server returns a 412". This used to read as no header, and the write
    // ran unconditionally (REVIEW-2026-10-17 finding 9). The value carries
    // characters no version id may hold, so it equals none.
    return 'malformed: $value';
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
  /// When 'strict', the server should return 400 for unrecognized search
  /// params.
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
                  'Resource ${statusCode == 201 ? "created" : "updated"} '
                          'successfully'
                      .toFhirString,
            ),
          ],
        );
        return Response(statusCode, body: oo.toJsonString(), headers: headers);
      default: // 'representation'
        return Response(
          statusCode,
          body: resource.toJsonString(),
          headers: headers,
        );
    }
  }
}
