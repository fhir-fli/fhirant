# A token must carry `exp` (ASVS V9.2.1), 2026-11-10

- `jwt_service_test.log`: the five new tests pass.
- `jwt_service_test_without_check.log`: with the `exp` check removed from
  `JwtService.verifyToken`, two of them fail (no `exp`, access and refresh).
- `server_suite.log`: full fhirant_server suite, 1,704 passed.
- `asvs_probes_rerun.tsv`, `access_grid_rerun.tsv`: `access_grid.py` then
  `asvs_probes.py` against the binary built by `dart build cli` from this
  branch. Against `owner_claim/asvs_probes_rerun.tsv` the one changed verdict
  is "token: no exp", FAIL (200) to PASS (401); the 285 rows of
  `owner_claim/access_grid_rerun.tsv` match by identity, label and method.
