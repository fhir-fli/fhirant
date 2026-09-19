# REVIEW-2026-09-17 triage: 12 OPEN

Scope: the 24 fhirant commits of 2026-09-19. The 27 of 2026-09-18 are not
classified yet.

Each item below changed behaviour **without** a reproduced defect against an
outside source (spec MUST, RFC, measurement, observed failure). Rule on each:
**keep** or **revert**. Revert is `git revert <commit>` plus the doc lines;
each is one commit. When an item is ruled, it is deleted here and the ruling
goes to `REVIEW_DECISIONS.md`.

| # | Commit | What changed | Evidence it was needed | Cost of keeping | My recommendation |
|---|---|---|---|---|---|
| 1 | `633d686` Q9 | Conditional create reads 2 rows, not all; `$export` type filter reads ids | None measured. Fewer rows read by construction | Small | Keep |
| 2 | `88f7cf6` Q8 | `_contained=true\|both` supported | The old refusal was conformant; only its message ("does not index contained resources") was false | Adds a second paging path and three refusals to the type search | Revert to the refusal with a true message, unless you want the feature |
| 3 | `50e06d3` A14 | Password change, deactivate, role and scopes routes; any change ends older sessions | Feature. Without it a leaked password is fixed only in the database | Six routes, schema 25 | Keep |
| 4 | `23b2b78` A16.1 | PKCE verifier accepts S256 only | The authorize endpoint already refused `plain`, so the path was unreachable | Removes code | Keep |
| 5 | `6c986cb` A16.4 | `X-Frame-Options`, CSP, `nosniff` on the login and error pages | OWASP recommendation; no framing attack shown | One header map | Keep |
| 6 | `1587d54` A16.5 | A reused refresh token logs the account out everywhere | RFC 9700 is best practice; the old behaviour met RFC 6749 | **A client whose refresh response is lost on a bad network retries with the old token and is logged out.** Matters for field use | Your call; this is the one with a clinical-workflow cost |
| 7 | `63c1f7c` A16.6 | `bind` needs a FHIR id, a stored Subscription, and at most 16 per socket | `/ws` already needs a token; pings carry no payload. 16 is my number | A DB read per bind | Revert |
| 8 | `1c14577` A16.7 | Backup iteration count capped at 10× what the server writes | Measured: a crafted file stalls the server about 80 minutes. But `$restore` is admin-only | A future 10× increase must move the cap | Keep |
| 9 | `8d378b7` A16.9 | Failed logins recorded as AuditEvents with the name tried | **Reverses the 2026-09-07 choice** (`d99bfe5`) not to record unauthenticated 401s, made to bound unauthenticated writes. Now bounded by the login rate limit | Up to 10 events per minute per address | Your call |
| 10 | `8a9e761` A16.11 | AuditEvents deleted after six years by default | **Unverified.** The six years is 45 CFR 164.316(b)(2)(i), whose text covers "documentation required by paragraph (b)(1)"; whether that includes audit-log entries is my reading. Nothing is deleted before 2032 | A default that deletes records | Revert to no deletion unless configured, unless you know the retention rule |
| 11 | `2a68322` S4 | `--dev-mode` no longer allows the public key; new `--allow-public-key` | Design choice; nothing failed | The dev command needs two flags | Keep |
| 12 | `0f313b0` S6 | `--config` now read (YAML); `http` pinned | The flag was dead. Deleting it was the smaller fix | A YAML dependency and a config loader | Your call: keep the loader or delete the flag |

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

Documentation only: `b952dc4` S7.
