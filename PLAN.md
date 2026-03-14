# PLAN.md — FHIRant Remaining Work

Living task list of genuinely incomplete features. Update checkboxes as work is completed.

---

## Search Gaps

- [ ] **_has (reverse chaining)** — e.g., `Patient?_has:Observation:patient:code=1234`. Test file exists (`has_search_e2e_test.dart`) but implementation incomplete.
- [ ] **_summary** — return subset of resource (true, data, text, count)
- [ ] **_elements** — return only specified fields
- [ ] **_contained / _containedType** — search within contained resources
- [ ] **_filter** — FHIRPath-based filtering parameter
- [ ] **Accent normalization** — for string search (TODO in codebase)

## Content & Format

- [ ] **XML support** — `application/fhir+xml` serialization (low priority; JSON-only by design for now)
- [ ] **_format parameter** — allow format override via query parameter

## HTTP Standards

- [ ] **ETag / If-Match** — version-aware conditional updates (return 412 on mismatch)
- [ ] **If-None-Exist** — conditional create
- [ ] **Prefer header** — `return=minimal` (204) vs `return=representation` (200 with body)

## Subscriptions

- [ ] **Subscription resource support** — create/manage subscriptions
- [ ] **REST-hook notifications** — POST to subscriber URL on resource change
- [ ] **WebSocket notifications** — real-time push (websocket_handler.dart exists but not functional)

## Advanced Operations

- [ ] **GraphQL endpoint** — FHIR GraphQL support
- [ ] **Profile validation** — validate against StructureDefinition profiles

## Testing Gaps

- [ ] **fhirant_secure_storage tests** — mock flutter_secure_storage, test key generation
- [ ] **fhirant_logging tests** — basic smoke tests for log levels and file output
- [ ] **Coverage reporting** — configure and track code coverage in CI
- [ ] **Conformance suite** — automated FHIR Touchstone or official test kit testing

## Deployment

- [ ] **Docker** — Dockerfile + docker-compose for standalone deployment
- [ ] **CI/CD** — GitHub Actions for test + analyze + build
- [ ] **iOS build** — build and test Flutter app on iOS device/simulator

## Mobile

- [ ] **iOS testing** — verify server lifecycle, SQLCipher, background behavior
- [ ] **Performance** — optimize for large databases (resource count refresh, isolate-based server)
