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

Built 2026-08-29. Criteria are matched by running them through the **same**
parser and the **same** database search the REST endpoint uses, with `_id`
pinned to the resource that just changed. R4 subscription.html requires
criteria to be "search strings interpreted identically to REST API queries",
and reimplementing parameter semantics beside the search engine is how that
stops being true.

- [x] **Subscription resource support** — the server decides the status, per
      the lifecycle: `requested` → `active` once it has validated it can
      process it, or `error` with the reason in `Subscription.error`. An
      unsupported channel is refused rather than accepted, because telling a
      client a subscription is active when nothing will ever be delivered is
      worse than saying no. `end` in the past turns it `off`.
- [x] **REST-hook notifications** — no payload POSTs an empty body to the
      endpoint; a payload PUTs the resource to `{endpoint}/{Type}/{id}`, the
      endpoint being "the nominated URL as the service base".
      `channel.header` is split on the first colon only.
- [x] **WebSocket notifications** — `websocket_handler.dart` was a one-byte
      file that `handlers.dart` exported. It now serves `/ws` and implements
      the handshake the spec gives: `bind :id` → `bound :id` → `ping :id`. No
      payload crosses the socket; the client re-runs its own criteria. The
      endpoint is advertised through HL7's `capabilitystatement-websocket`
      extension, without which a client cannot find it.
- [x] **Notifications fire from every write path** — POST, PUT, and the
      create, update and patch entries of a Bundle. For a transaction they are
      sent **after the commit**, because a transaction is all-or-nothing and a
      rest-hook POST cannot be recalled. A DELETE sends nothing, per the spec.
- [x] **A Subscription created through a Bundle entry is activated too** —
      closed 2026-08-29. It was a way to store a subscription the server had
      never validated, which the single-resource endpoints do not allow. Create,
      update and patch entries all go through activation; a patch because it can
      change the criteria or the channel, so the server has to decide again.
- [x] **Retry and automatic `off`** — closed 2026-08-29, and it uncovered a
      worse bug: `error` was **terminal**. `onResourceChanged` searched only for
      `status=active`, so the first failed delivery silenced a subscription for
      good while stamping it with a status the spec says can revert to active.
      Deliverable statuses are now `active` **and** `error`; only `off` (given
      up) and `requested` (not yet accepted) are excluded.
      🛑 **The retry numbers are fhirant policy, not spec rules.** R4
      subscription.html delegates it: the server "**may** retry the
      notification a fixed number of times" and "**may** choose set the
      subscription status to off". Five consecutive failures switches it off,
      configurable, and a success resets the count so failures spread over time
      never add up. The count lives in an extension under our own namespace
      because R4 models no element for it and an in-memory counter would reset
      every time the phone backgrounds the server.
- [x] **`Subscription.end` is swept** — closed 2026-08-29 by hanging
      `sweepExpired()` on the hourly cleanup timer that already prunes revoked
      tokens, rather than adding a second timer. ⚠️ Correcting an earlier note:
      an expired subscription **never delivered**; `onResourceChanged` checks
      `end` before it matches. What was wrong was the **stored status**, which
      stayed `active` until some unrelated write triggered an evaluation, so a
      client reading the resource on a quiet server was told `active` about a
      finished subscription. R4 calls `end` "the time for the server to turn
      the subscription off", which is an instruction to the server.
- [ ] **Only rest-hook and websocket** — email, sms and message are refused at
      activation rather than silently accepted.

## Advanced Operations

- [ ] **GraphQL endpoint** — FHIR GraphQL support. Nothing exists.
- [ ] **Profile validation** — validate against StructureDefinition profiles
- [x] **`$transform`** — fixed 2026-08-29 and now has tests
      (`test/handlers/mapping_handler_test.dart`, 10). It had none, and it was
      broken: the handler passed a **null target** to `fhirMappingEngine`,
      which cannot invent one and throws `Unable to create target of type
      <alias>`, so every real transform returned 500. The target now comes from
      the map's own `structure` entry with `mode = target`, and the resource
      type from that definition's `type` element — `1..1`, "the type this
      structure describes". Checked against the published definitions in
      `~/.fhir/packages`: base `Patient` carries `type: "Patient"`, and the
      profile `us-core-patient` carries `type: "Patient"` too.
      🛑 structuremap.html gives **no** rule for resolving the canonical to a
      type at execution; an earlier version of this entry and of the code
      comment cited it for one, wrongly. Twelve tests.
- [x] **`SimpleResourceCache` stubs** — replaced 2026-08-29 by
      `DbResourceCache`, backed by the server's own database, so a
      StructureDefinition, ValueSet, CodeSystem, ConceptMap or StructureMap
      POSTed to this server is what a transform resolves against. `client`
      stays null: no network, because the device may not have one.
      🛑 **Measured, and narrower than it was claimed to be.** A counting
      cache recorded **zero** calls from inside the mapping engine across a
      same-type copy, a cross-type copy, a nested `create` and a profiled
      target, and an A/B against the old throwing implementation passed
      identically. The stubs were a latent trap in a public contract, not a
      live engine failure. The only caller today is the target-type
      resolution.
- [ ] **A target with required elements** — a map that does not set
      `Observation.status`, `Basic.code` or `RelatedPerson.patient` cannot be
      built, and `FhirMapEngine.transformBuilder` reports that by **returning
      an OperationOutcome rather than throwing**. The handler returned it with
      **HTTP 200**; it now returns **422** with the outcome. The open half is
      `fhir_r4_mapping`, not fhirant: whether `Builder.build()` should throw a
      null-check error at all, or name the unset required element.
- [ ] **A canonical the server does not hold** — resolution falls back to the
      last path segment of the URL, which is right for a base FHIR canonical
      and wrong for an unheld profile, so the caller gets a 400 naming what
      could not be resolved rather than a guessed type. Deviation, labelled in
      the code. The cure is to POST the StructureDefinition first.
- [ ] **Several target structures** — `structure` is `0..*`. The handler takes
      the first `mode = target` entry and ignores any others. No spec rule
      found either way; recorded rather than assumed correct.

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

- [x] **`backup_crypto_test.dart` "no patient data appears in the envelope"**
      — searched the whole envelope for the patient id `p1`. The envelope is
      mostly random base64, so two characters occur by chance: **measured 15
      hits in 200 encryptions, 7.5%**, on a test whose job is to say whether
      patient data escaped. Id lengthened to `pat-9f3c2a71-leak-canary`,
      0 in 200. Fixed 2026-08-29.
- [ ] **`export_integration_test.dart` "Cancel export DELETE cancels and
      cleans up"** — failed once in a full-suite run on 2026-08-29 with
      "Export job did not complete within max attempts", then passed 3/3 run
      alone. It polls with a fixed attempt count, so it times out under
      whole-suite load rather than failing. Poll on a deadline, not a count.

## Suite baseline — 2026-08-29

Whole suites, no file arguments. `dart analyze` clean in all five packages.

| package | runner | tests |
|---|---|---|
| `fhirant_server` | `dart test` | 762 |
| `fhirant_db` | `dart test` | 110 |
| `fhirant` | `flutter test` | 33 |
| `fhirant_secure_storage` | `flutter test` | 11 |
| `fhirant_logging` | — | **no test directory** |
