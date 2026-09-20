# Review decisions

Rulings on review findings. A reviewer reads this before reporting and does
not re-raise a ruled item without new evidence. A fixer reads it before
changing code.

What counts as a finding worth fixing (agreed 2026-09-19): the current
behaviour is reproduced as wrong against something outside our code (a spec
requirement, an RFC, a measurement, an observed failure). A test that fails
without the fix proves only that the test exercises the fix. Anything else
is hardening or a feature and goes to triage (`REVIEW-2026-09-17-TRIAGE.md`)
before it is built.

## Rulings

- 2026-09-19, Q9 (`633d686`) conditional create reads at most 2 rows; `$export` type filter reads ids: **keep**. Unmeasured, but same answers with less reading, and reverting would be a change with no benefit.
- 2026-09-19, Q8 (`88f7cf6`, fhir_db `8401ad9`) `_contained=true|both`: **revert, for now**. The spec defines it without requiring it and nothing we build uses it; refused with a true message. To be built out later.
- 2026-09-19, A14 (`50e06d3`) account management and the token-generation counter: **keep**. Feature; the counter also carries the RFC 9700 refresh-reuse and RFC 6749 code-reuse revocations.
- 2026-09-19, A16.1 (`23b2b78`) PKCE verifier accepts S256 only: **keep**. Removes an unreachable `plain` branch that contradicted the authorize check (RFC 7636 §7.2).
- 2026-09-19, A16.4 (`6c986cb`) frame, CSP, nosniff and no-store headers on the login and error pages: **keep**. OWASP recommendation; nothing we build frames the page.
- 2026-09-19, A16.6 (`63c1f7c`) websocket bind limits: **revert**. Guarded nothing observed; missed the only exposure (binding another user's Subscription, no ownership check). That exposure is not ruled on.
- 2026-09-19, A16.7 (`1c14577`) backup iteration ceiling at 10× what fhirant writes: **keep**. Measured: a crafted file would hold the server isolate about 80 minutes; the ceiling costs one comparison.
- 2026-09-19, S4 (`2a68322`) `--dev-mode` split from the public key: **keep, with `--dev-mode` implying `--allow-public-key`**. The driver at this stage is testers stress-testing use, not security, so a test server takes one flag; authentication on still needs the explicit flag.

## Settled by a source (2026-09-19)

- A16.5 refresh-token reuse ends the grant: required, RFC 9700 §4.14.2 MUST for public clients.
- A16.9 failed logins audited: kept, 45 CFR 164.308(a)(5)(ii)(C) log-in monitoring.
- A16.11 audit retention: no deletion by default; a deployment sets its own period (NIST SP 800-66r2 §5.3.2).
