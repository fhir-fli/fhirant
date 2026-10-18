import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:fhirant_server/src/utils/no_store.dart';
import 'package:shelf/shelf.dart';

/// [noStoreHeaders] on every response to an authenticated request that did
/// not set its own Cache-Control.
///
/// OWASP ASVS 5.0.0 V14.3.2 (L2, read 2026-10-17, verbatim): "Verify that the
/// application sets sufficient anti-caching HTTP response header fields
/// (i.e., Cache-Control: no-store) so that sensitive data is not cached in
/// browsers." A Patient read, a search and $everything carried none
/// (REVIEW-2026-10-17 finding 16). What needs a credential is what may hold
/// patient data; the public discovery documents, fetched without one, are
/// left cacheable.
Middleware noStoreForAuthenticated() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      if (Principal.of(request) == null) return response;
      if (response.headers.containsKey('cache-control')) return response;
      return response.change(headers: noStoreHeaders);
    };
  };
}
