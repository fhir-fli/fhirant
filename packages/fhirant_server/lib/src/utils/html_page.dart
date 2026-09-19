/// Headers for the HTML pages this server serves: the login form and the
/// authorization error pages (REVIEW-2026-09-17 A16: they carried no frame
/// or content-security header).
///
/// OWASP Clickjacking Defense Cheat Sheet (raw markdown read 2026-09-19,
/// verbatim): `Content-Security-Policy: frame-ancestors 'none';` "This
/// prevents any domain from framing the content. This setting is
/// recommended unless a specific need has been identified for framing."
/// and `X-Frame-Options: DENY` "The 'DENY' setting is recommended unless a
/// specific need has been identified for framing." Both, since older
/// agents read only the second.
///
/// OWASP Content Security Policy Cheat Sheet (same day, verbatim):
/// `form-action` "restricts the URLs which the forms can submit to";
/// `base-uri` "specifies the possible URLs that the `<base>` element can
/// use"; `default-src` "is a fallback directive for the other fetch
/// directives". The pages carry one inline `<style>` and no script, so
/// nothing but inline style is allowed to load, the form may post only
/// here, and `<base>` may not be set.
const Map<String, String> htmlPageHeaders = {
  'Content-Type': 'text/html; charset=utf-8',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; "
      "form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Cache-Control': 'no-store',
};
