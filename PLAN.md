# PLAN.md — FHIRant Remaining Work

Living task list of genuinely incomplete features. Update checkboxes as work
is completed.

🛑 **Checked against the code on 2026-08-29, not trusted.** Seven items were
marked open that are implemented; the CORS allowed-headers list had been
mistaken for the absence of an implementation, in both directions. A stale plan sends work at
things that are already done, so confirm against the source before picking
an item up, and record what you checked.

**Second pass, same day**, prompted by "is there anything left?": three more
items were open that are done (Docker, secure-storage tests, an accent
normalization TODO that is in no file), and `$transform` — advertised in the
CapabilityStatement, gated by a SMART scope — was returning 500 on every real
transform with no test covering it. Verifying the plan is how that was found.

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
- [ ] **Accent normalization** — for string search. R4 search.html: string
      search "is insensitive to ... accents". Not implemented; there is no
      TODO in the codebase either, the plan's old note was wrong (grepped
      accent/diacritic/normaliz case-insensitively across all five packages,
      2026-08-29).

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
- [ ] **WebSocket notifications** — real-time push. `websocket_handler.dart`
      is an **empty file** that `handlers.dart` still exports, and no
      `Subscription` appears anywhere in `fhirant_server/lib`. Either write the
      handler or delete the empty file and its export; an empty exported
      handler reads as a half-built feature. Verified 2026-08-29.

## Advanced Operations

- [ ] **GraphQL endpoint** — FHIR GraphQL support. Nothing exists.
- [ ] **Profile validation** — validate against StructureDefinition profiles
- [x] **`$transform`** — fixed 2026-08-29 and now has tests
      (`test/handlers/mapping_handler_test.dart`, 10). It had none, and it was
      broken: the handler passed a **null target** to `fhirMappingEngine`,
      which cannot invent one and throws `Unable to create target of type
      <alias>`, so every real transform returned 500. The target now comes from
      the map's own `structure` entry with `mode = target`, per R4
      structuremap.html. Measured one variable at a time: with a target
      supplied the transform succeeds under the handler's existing
      `SimpleResourceCache`, so the `UnimplementedError` stubs in that class
      were not the cause.
- [ ] **A target with required elements** — a map that does not set
      `Observation.status`, `Basic.code` or `RelatedPerson.patient` cannot be
      built, and `FhirMapEngine.transformBuilder` reports that by **returning
      an OperationOutcome rather than throwing**. The handler returned it with
      **HTTP 200**; it now returns **422** with the outcome. The open half is
      `fhir_r4_mapping`, not fhirant: whether `Builder.build()` should throw a
      null-check error at all, or name the unset required element.
- [ ] **`SimpleResourceCache` stubs** — `getStructureDefinition`,
      `getStructureDefinitions`, `getResourceMap`, `getResourceNames`,
      `getCodeSystem` and `client` all throw `UnimplementedError`. Not reached
      by the transforms tested above, but `WorkerContext.fetchTypeDefinition`
      calls `getStructureDefinition`, so a map needing element resolution
      across types will hit it. Not yet measured.

## Testing Gaps

- [x] **fhirant_secure_storage tests** — 11 tests in
      `test/key_generation_test.dart` covering `generateSecureRandomKey` and
      `certificateFingerprint`; green under `flutter test` 2026-08-29. Mocking
      `flutter_secure_storage` itself is still not done.
- [ ] **fhirant_logging tests** — basic smoke tests for log levels and file output
- [ ] **Conformance suite** — automated FHIR Touchstone or official test kit testing

## Deployment

- [x] **Docker** — `Dockerfile`, `docker-compose.yml` and `test_docker.sh` are
      all in the repo root. Verified present 2026-08-29; not run.
- [x] **CI/CD** — `.github/workflows/ci.yml`, added 2026-08-29. Formats,
      analyzes and tests all five packages on push to `main`, on every pull
      request, and on demand. Each package is checked even when an earlier one
      fails, so a failure in `fhirant_db` cannot hide `fhirant_server`.
      Rehearsed before committing, against a clean clone pair, both
      directions: green run 868 tests across five packages, exit 0; with a
      deliberate failure injected into `fhirant_db` (second alphabetically)
      exit 1, `fhirant_db` named, and the three packages after it still ran.
- [ ] **`fhirant_server` depends on `cicada` by a path that leaves this repo**
      (`../../../cicada/cicada`). A clone of fhirant alone therefore cannot
      resolve, build or test. CI works around it by checking out both repos
      side by side, which is why this repo is checked out into a `fhirant/`
      subdirectory. The real fix is for cicada to be a git or hosted
      dependency; until then the layout is load-bearing and undocumented
      outside `ci.yml`.
- [ ] **Coverage reporting** — still not configured; now that CI exists this
      is a step in `ci.yml`, not a new piece of infrastructure.
- [ ] **iOS build** — build and test Flutter app on iOS device/simulator

## Mobile

- [ ] **iOS testing** — verify server lifecycle, SQLCipher, background behavior
- [ ] **Performance** — optimize for large databases (resource count refresh, isolate-based server)

## Flaky

- [ ] **`export_integration_test.dart` "Cancel export DELETE cancels and
      cleans up"** — failed once in a full-suite run on 2026-08-29 with
      "Export job did not complete within max attempts", then passed 3/3 run
      alone. It polls with a fixed attempt count, so it times out under
      whole-suite load rather than failing. Poll on a deadline, not a count.

## Suite baseline — 2026-08-29

Whole suites, no file arguments. `dart analyze` clean in all five packages.

| package | runner | tests |
|---|---|---|
| `fhirant_server` | `dart test` | 714 |
| `fhirant_db` | `dart test` | 110 |
| `fhirant` | `flutter test` | 33 |
| `fhirant_secure_storage` | `flutter test` | 11 |
| `fhirant_logging` | — | **no test directory** |
