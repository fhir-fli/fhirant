# REVIEW-2026-09-17 triage: 6 OPEN

Scope: the 24 fhirant commits of 2026-09-19. The 27 of 2026-09-18 are not
classified yet.

Each item below changed behaviour **without** a reproduced defect against an
outside source (spec MUST, RFC, measurement, observed failure). Rule on each:
**keep** or **revert**. Revert is `git revert <commit>` plus the doc lines;
each is one commit. When an item is ruled, it is deleted here and the ruling
goes to `REVIEW_DECISIONS.md`.

| # | Commit | What changed | Evidence it was needed | Cost of keeping | My recommendation |
|---|---|---|---|---|---|
| 4 | `23b2b78` A16.1 | PKCE verifier accepts S256 only | The authorize endpoint already refused `plain`, so the path was unreachable | Removes code | Keep |
| 5 | `6c986cb` A16.4 | `X-Frame-Options`, CSP, `nosniff` on the login and error pages | OWASP recommendation; no framing attack shown | One header map | Keep |
| 7 | `63c1f7c` A16.6 | `bind` needs a FHIR id, a stored Subscription, and at most 16 per socket | `/ws` already needs a token; pings carry no payload. 16 is my number | A DB read per bind | Revert |
| 8 | `1c14577` A16.7 | Backup iteration count capped at 10× what the server writes | Measured: a crafted file stalls the server about 80 minutes. But `$restore` is admin-only | A future 10× increase must move the cap | Keep |
| 11 | `2a68322` S4 | `--dev-mode` no longer allows the public key; new `--allow-public-key` | Design choice; nothing failed | The dev command needs two flags | Keep |
| 12 | `0f313b0` S6 | `--config` now read (YAML); `http` pinned | The flag was dead. Deleting it was the smaller fix. No outside source bears on it | A YAML dependency and a config loader | Keep: it is built and tested, and deleting it now is more change |

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
