/// Headers for a response that carries a token, an authorization code or
/// a credential. RFC 6749 §5.1 (read 2026-09-19, verbatim): "The
/// authorization server MUST include the HTTP "Cache-Control" response
/// header field [RFC2616] with a value of "no-store" in any response
/// containing tokens, credentials, or other sensitive information, as well
/// as the "Pragma" response header field [RFC2616] with a value of
/// "no-cache"." No token response carried either (REVIEW-2026-09-17 A16).
const Map<String, String> noStoreHeaders = {
  'Cache-Control': 'no-store',
  'Pragma': 'no-cache',
};

/// [noStoreHeaders] for a JSON body.
const Map<String, String> jsonNoStoreHeaders = {
  'Content-Type': 'application/json',
  ...noStoreHeaders,
};
