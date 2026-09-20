# REVIEW-2026-09-17 triage: NOTHING IS OPEN

All twelve items were ruled on 2026-09-19; the rulings are in
`REVIEW_DECISIONS.md`. What remains below is the record of the day's 24
commits. Do not re-raise a ruled item without new evidence.

Scope: the 24 fhirant commits of 2026-09-19 and the 26 of 2026-09-18.


## Reproduced defects (no ruling needed)

Each had the old behaviour observed wrong against an outside source.

- `aa05393` C7: `$translate` returned only the first match.
- `6c48492` D1: a restore over a newer local version overwrote its history (data loss).
- `2415388` A12: login answered deactivated 403, unknown 401, locked 423 (OWASP).
- `b243dad` A13: a patient token saw 403 for another patient's record and 404 for none (existence oracle).
- `5411bf0` A15: the first network registrant became administrator (observed in the Docker smoke test).
- `7a5bb39` A16.2: two exchanges of one authorization code both got tokens (RFC 6749 §4.1.2 MUST).
- `f4cbeb2` A16.3: token responses had no `Cache-Control: no-store` (RFC 6749 §5.1 MUST).
- `478a3c2` A16.8, fhir_db `c6ca785`: compartment membership ignored the server's base URL (the reference search already applied it).
- `95b50bb` A16.10: `saveResources` catches every exception and returns false, so every failed audit write vanished without a log line.
- `2c28392` S5: the old health check marked every container unhealthy.
- `0f313b0` S6, the port half: `--port abc` crashed with a stack trace, exit 255.
- `d57f4dc` S8: clean builds took whatever the dependency branches held that minute.
- `1587d54` A16.5: a reused refresh token was answered 401 and nothing else. RFC 9700 §4.14.2 (verbatim): "Authorization servers MUST utilize one of these methods to detect refresh token replay by malicious actors for public clients"; fhirant authenticates no client, so every client is public. The RFC names the cost itself: "at the cost of forcing the legitimate client to obtain a fresh authorization grant".

## Settled by a source (no ruling needed)

- `8d378b7` A16.9, failed logins audited: **kept.** 45 CFR 164.308(a)(5)(ii)(C) (law.cornell.edu, verbatim): "Log-in monitoring (Addressable). Procedures for monitoring log-in attempts and reporting discrepancies." The 2026-09-07 exclusion was a session's choice, not a ruling, and its reason (unbounded unauthenticated writes) is now bounded by the login rate limit.
- `8a9e761` A16.11, audit retention: **default changed to no deletion.** No source sets a retention period for audit records: NIST SP 800-66r2 §5.3.2 (Audit Controls, read whole) leaves it to "the regulated entity's risk assessment", and §164.316(b)(2)(i) covers "documentation required by paragraph (b)(1)". The HHS January 2017 audit-controls newsletter and OCR audit protocol refused automated access (HTTP 403) and were not read. Retention runs only when a deployment sets `--audit-retention-days`.

## New finding, reproduced, not yet fixed

- Every AuditEvent carries `type` `110112` Query, a failed login included. The R4B value set `audit-event-type` has `110114` User Authentication for that event.

Documentation only: `b952dc4` S7.

## 2026-09-18: 26 commits, nothing to rule

Classified 2026-09-20 against the same bar. Every one fixed behaviour that
had been reproduced wrong, or was measured:

- Probe-confirmed in the review before any fix: A1, A2, A3, A5, A6 (one
  commit, `c30c724`), A7, A8, A9, A10, S1, S2, Q1, Q2, Q3, Q4, Q5, Q6, Q7,
  C1, C2, C3, C5, C6, and the second Q8 (a code element's implicit system:
  `status=<system>|final` matched nothing).
- A11, password hashing: measured at 290-337 ms of PBKDF2 on the server
  isolate, against the OWASP Password Storage Cheat Sheet.
- C4, `oauth-uris` advertising `register`: read, not probed. The extension's
  `register` is OAuth 2.0 dynamic client registration (RFC 7591); fhirant's
  `/auth/register` creates user accounts, so the advertisement pointed
  clients at the wrong thing.
- `17c5641` WAL with `synchronous=FULL`: measured, 7.9 ms per commit against
  23.8 with a rollback journal. `NORMAL` is settled and not revisited.
- `0a47b75` and `fa6df52`: reproduced (a backup whose random salt starts with
  `{`, 1 in 256; then malformed JSON). Both repaired a detector this same
  day's work had introduced, which is churn, not review noise.
- `2a54291`: test-only, after Q1 moved dates to the UTC clock.

So the drift is dated: it began on 2026-09-19, in the review's own "Smaller,
BY READING" bucket (A16) and the S items.
