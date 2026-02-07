import 'dart:io';

import 'package:fhir_r4/fhir_r4.dart' as fhir;

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
}
