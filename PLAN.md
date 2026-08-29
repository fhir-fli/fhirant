# PLAN.md — FHIRant Remaining Work

Living task list of genuinely incomplete features. Update checkboxes as work
is completed.

🛑 **Checked against the code on 2026-08-29, not trusted.** Six items were
marked open that are implemented and tested. A stale plan sends work at
things that are already done, so confirm against the source before picking
an item up, and record what you checked.

---

## Search Gaps

- [x] **_has (reverse chaining)** — implemented. `has_search_e2e_test.dart`
      has 6 tests that create data, run the search and assert the returned
      resource by id. Verified 2026-08-29.
- [x] **_summary** — implemented: parsed in `search_parser.dart`, applied as
      response shaping in `resource_handler.dart`, `_summary=count` short-
      circuits to a total-only bundle. Verified 2026-08-29.
- [x] **_elements** — implemented alongside `_summary`, including the
      mutual-exclusivity check the spec requires. Verified 2026-08-29.
- [ ] **_contained / _containedType** — recognised as valid parameter names
      so they are not rejected, but nothing acts on them.
- [ ] **_filter** — recognised as a valid parameter name only; nothing acts
      on it. (`_filterContains` in `terminology_handler.dart` is ValueSet
      expansion filtering, unrelated.)
- [ ] **Accent normalization** — for string search (TODO in codebase)

## Content & Format

- [ ] **XML support** — `application/fhir+xml` serialization (low priority; JSON-only by design for now)
- [x] **_format parameter** — honoured by `content_negotiation.dart`, which
      checks it alongside Accept and returns 406 for unsupported types.
      Verified 2026-08-29.

## HTTP Standards

- [ ] **ETag / If-Match** — still open. Both appear only in the CORS
      allowed-headers list, which is not an implementation.
- [x] **If-None-Exist** — implemented in `resource_handler.dart`: runs the
      search, returns the existing resource on one match and a `duplicate`
      OperationOutcome on several. Verified 2026-08-29.
- [ ] **Prefer header** — still open, and likewise only in the CORS
      allowed-headers list.

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
