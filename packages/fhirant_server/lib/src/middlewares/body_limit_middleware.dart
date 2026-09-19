import 'dart:async';

import 'package:fhirant_server/src/auth/request_authorization.dart';
import 'package:shelf/shelf.dart';

/// Refuses a request body larger than [maxBytes] with 413, before anything
/// reads it (REVIEW-2026-09-17 A10: a 20 MB Patient was accepted, and every
/// write route reads its body whole; on a phone that is memory).
///
/// A body that declares its length is refused from the header. One that
/// does not is read up to the cap and refused as soon as the cap is passed;
/// what was read is handed on as the body, so a handler reads it as it
/// always did. Paths in [uncapped] are passed through untouched: `$restore`
/// streams its body to disk by design.
///
/// RFC 9110 §15.5.14 (read 2026-09-18): 413 "Content Too Large" is the
/// status for "a request content larger than the server is willing or able
/// to process".
/// The default cap: 16 MiB. The largest bodies this server takes whole are
/// transaction Bundles; the 500-Patient Bundles of the 2026-09-18 reindex
/// check were about 60 KB each (computed from their entries, not
/// measured). No real deployment's Bundles have been measured: nobody but
/// us has one. Configurable per server (`FhirAntServer.maxRequestBody`).
const int kMaxRequestBody = 16 * 1024 * 1024;

Middleware bodyLimitMiddleware(
  int maxBytes, {
  Set<String> uncapped = const {r'$restore'},
}) {
  return (Handler inner) {
    return (Request request) async {
      final path = request.url.path;
      if (uncapped.contains(path)) return inner(request);
      final declared = request.contentLength;
      if (declared != null && declared > maxBytes) {
        return _tooLarge(declared, maxBytes);
      }
      if (declared == 0 ||
          request.method == 'GET' ||
          request.method == 'HEAD') {
        return inner(request);
      }
      final chunks = <List<int>>[];
      var total = 0;
      await for (final chunk in request.read()) {
        total += chunk.length;
        if (total > maxBytes) return _tooLarge(null, maxBytes);
        chunks.add(chunk);
      }
      return inner(request.change(body: Stream.fromIterable(chunks)));
    };
  };
}

Response _tooLarge(int? declared, int maxBytes) => outcomeResponse(
      413,
      'too-costly',
      'The request body${declared == null ? '' : ' of $declared bytes'} is '
          'larger than this server accepts ($maxBytes bytes).',
    );
