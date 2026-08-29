# PLAN.md — FHIRant Remaining Work

Living task list of genuinely incomplete features. Update checkboxes as work
is completed.

🛑 **Checked against the code on 2026-08-29, not trusted.** Seven items were
marked open that are implemented; the CORS allowed-headers list had been
mistaken for the absence of an implementation, in both directions. A stale plan sends work at
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
- [ ] **_contained / _containedType** — recognised so a lenient request is
      not rejected, and now reported under `Prefer: handling=strict`.
      Still not acted on. Optional in R4: "servers are not obliged to
      support this parameter."
- [ ] **_filter** — same: recognised, reported under strict handling, not
      acted on. Optional in R4. (`_filterContains` in
      `terminology_handler.dart` is ValueSet expansion filtering,
      unrelated.)
- [ ] **Accent normalization** — for string search (TODO in codebase)

## Content & Format

- [ ] **XML support** — `application/fhir+xml` serialization (low priority; JSON-only by design for now)
- [x] **_format parameter** — honoured by `content_negotiation.dart`, which
      checks it alongside Accept and returns 406 for unsupported types.
      Verified 2026-08-29.

## HTTP Standards

- [x] **ETag / If-Match** — implemented. `FhirHttpHeaders.resourceHeaders`
      puts a weak `W/"versionId"` ETag on read, create and update;
      `resource_handler.dart:865` compares If-Match to the stored versionId
      and returns **412 Precondition Failed** on mismatch, and on a missing
      resource. Matches R4 http.html: "If the version id given in the
      If-Match header does not match, the server returns a 412 Precondition
      Failed status code instead of updating the resource." Verified
      2026-08-29 against the spec, not from memory.
- [x] **If-None-Exist** — implemented in `resource_handler.dart`: runs the
      search, returns the existing resource on one match and a `duplicate`
      OperationOutcome on several. Verified 2026-08-29.
- [x] **Prefer header** — implemented. `parsePreferReturn` handles
      `return=minimal`, `representation` and `OperationOutcome`;
      `parsePreferHandling` handles `handling=strict`/`lenient` for
      unrecognised search parameters. Verified 2026-08-29.

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
