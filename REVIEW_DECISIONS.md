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

None yet.
