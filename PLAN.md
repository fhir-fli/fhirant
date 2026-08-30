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
- [x] **Accent normalization** — done 2026-08-30 in `fhir_r4_db` 0.10.0, not
      here. The string index now holds a folded value for the default and
      `:contains` searches and the verbatim value for `:exact`, so
      `family=Munoz` finds `Muñoz` and `family:exact=munoz` no longer matches
      `Munoz`. Schema 5 → 6, index rebuilt from the stored resources on open.
- [x] **Search modifiers and comparators** — they were unreachable. The engine
      read both off the END of the value, a syntax FHIR does not have, so
      `:exact`, `:contains`, `:missing`, date ranges and the rest returned
      nothing to a conforming client, and a value containing a colon returned
      the WRONG record. Measured through this server: 7 of 41 queries worked,
      now 41. Fixed in `fhir_r4_db` 0.10.0; this server returns the 400 the
      spec requires for a modifier it cannot support.
- [x] **Comma escaping in the query parser** — done 2026-08-30, and not where
      this entry said it was. Search parameter values are no longer split
      here at all: `search_parser.dart` passes each repetition on raw, and
      `fhir_r4_db` splits it with `splitEscaped(value, ',')`
      (`lib/src/search/search_escaping.dart`), alongside the pipe and dollar
      halves it already handled. Values compared whole go through
      `unescapeValue`. Covered end to end through this server by
      `test/handlers/search_and_or_test.dart` "an escaped comma is one value,
      not two": an Organization named `Clinic, North Wing` is found by
      `name=Clinic\, North` and the plain `Clinic` is not.
      The raw `value.split(',')` calls left in `search_parser.dart` are on
      `_sort`, `_include`, `_revinclude`, their `:iterate` forms and
      `_elements`. R4 3.1.1.4.19 puts escaping on "an actual parameter
      value"; the items in those lists are parameter, element and resource
      type names, so a literal comma cannot occur in one. No spec rule was
      found extending escaping to them either way.

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
- [x] **fhirant_logging tests** — 6 tests in
      `test/fhirant_logging_test.dart`, added 2026-08-30: the three levels and
      their JSON shape, the error and stack trace fields, a null path writing
      no file, and re-initialization. The package had none, and writing them
      found a defect: `initialize()` called `Logger.root.onRecord.listen`
      without holding the subscription, and `onRecord` is a broadcast stream,
      so every call added another listener that wrote the same record again.
      Measured before the fix: the second test in the file already saw each
      record 3 times and the sixth saw it 10 times. `initialize` now cancels
      the previous subscription before it subscribes. The app initializes
      once; the server tests initialize per test in one process, which is
      where the duplicates were landing, including in the file
      `log_file_contents_test.dart` reads for finding F6.
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
- [x] **`fhirant_server` depends on `cicada` by a path that leaves this repo**
      — fixed 2026-08-30. It is a git dependency on `fhir-fli/cicada`,
      `path: cicada`, `ref: main`, and the lock pins the commit. `ci.yml` is
      back to a single checkout with no `working-directory`, and the repo no
      longer has to sit in a subdirectory. Rehearsed against a fresh clone
      with no cicada beside it: all five packages resolved and analyzed, and
      cicada came down from git at the pinned commit. Four passed outright.
      `fhirant_server` failed that first run on the export stall below —
      a test timeout, not a resolution problem, and the same clone then
      passed 775/775 twice in a row. Working on cicada and fhirant together
      now needs a `pubspec_overrides.yaml` in `packages/fhirant_server`,
      which is already gitignored.
- [x] **Coverage reporting** — added 2026-08-30 as a separate `coverage` job
      in `ci.yml`. It does not gate anything and runs **weekly (Sunday 04:00
      UTC) or on demand**, not on every push, because of what it costs:
      `fhirant_server`'s 775 tests take **35 seconds** normally, **wedge**
      under `dart test --coverage` at default parallelism (stuck at test 193
      for 6 minutes at 90% CPU and 2.7 GB), and take **16m59s** with
      `--concurrency=1`, which is where the 775/775 came from. Line coverage
      measured that way: **fhirant_server 80.1%** (4150/5181), fhirant 35.1%
      (332/945), fhirant_db 22.2% (81/365), fhirant_secure_storage 22.1%
      (21/95), fhirant_logging 100% (28/28). The job writes a table to the run
      summary and uploads every `lcov.info`. **No threshold is enforced** —
      nothing should fail on a number nobody has agreed to yet.
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
- [ ] **An export job occasionally never finishes** (was filed as a flaky
      test). The poll helper now runs on a 20-second wall-clock deadline
      instead of 20 attempts of a 100ms sleep, and its failure names the job,
      the elapsed budget, the number of polls and the last `X-Progress` line.
      🛑 **The stall itself is real and unexplained, so this stays open.**
      The old text here — "it times out under whole-suite load" — was a
      hypothesis written as a finding. What is measured, 2026-08-30, eight
      whole-suite runs: **55 polls in five runs returned on the FIRST
      attempt**, and one run — the first against a fresh clone — hung until
      `dart test`'s own 30-second per-test timeout killed it, on
      `_typeFilter combined with _since` rather than the cancel test, so the
      helper is not the subject. Two immediate reruns in that same clone
      passed 775/775. One occurrence in eight runs, on two different tests.
      The deadline is deliberately **under** the framework's 30 seconds so
      the next occurrence reports what it saw instead of "timed out". The
      framework timeout is not being raised: an export that hangs is a defect
      to fail on, not one to wait out.
      Next step when it recurs: the message will say whether the job was
      still `Queued` or `Exporting...`, which separates a job that never
      started from one that never finished.

## Suite baseline — 2026-08-29

Whole suites, no file arguments. `dart analyze` clean in all five packages.

| package | runner | tests |
|---|---|---|
| `fhirant_server` | `dart test` | 762 |
| `fhirant_db` | `dart test` | 110 |
| `fhirant` | `flutter test` | 33 |
| `fhirant_secure_storage` | `flutter test` | 11 |
| `fhirant_logging` | — | **no test directory** |
