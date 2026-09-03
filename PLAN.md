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
- [x] **_contained / _containedType** — settled 2026-09-02, as far as this
      server can go. R4 search.html: "_contained — Whether to return resources
      contained in other resources in the search matches. true | false | both
      (false is default)".
      `false`, and an absent parameter, are the default and are what this
      server does, so they are answered normally rather than reported as
      unsupported. `true` and `both` are refused with a 400 under **any**
      `Prefer` header, because answering with container matches would tell the
      client its search had covered contained resources. A value outside
      `true|false|both` is refused, as is a `_containedType` outside
      `container|contained`; `_containedType` alongside `_contained=false`
      cannot change the answer and is not an error on its own.
      **The measurement the refusal rests on**, kept as a test so it cannot
      quietly change: saving an Observation carrying a contained Patient
      stores the Observation and nothing else, and the contained Patient is
      not indexed.
      ⏭️ Answering `_contained=true` means indexing resources held in another
      resource's `contained` element, which is a change to `fhir_r*_db`'s
      extraction and storage — contained resources have no independent
      identity, `#inner` meaning something only inside its container.
- [x] **_filter** — done 2026-09-02, end to end. Parser
      (`filter_expression.dart`, 24 tests), evaluator
      (`filter_evaluator.dart`, 18), and wired into the search handler
      (`filter_e2e_test.dart`, 7 through HTTP against the real database).
      Every leaf runs as an ordinary search through the same index the REST
      endpoint uses; `and`/`or`/`not` combine the id sets; the result is
      ANDed with the ordinary parameters as `_id`, and intersected rather
      than appended when a patient compartment has already narrowed `_id`.
      **What it refuses, with a message and a 400 rather than a wrong
      answer:** `eq` on a string (3.1.3.2 means the whole value compared
      case-insensitively; we have starts-with and `:exact`), `ne` (not the
      complement of `eq` for a repeating element), `ew`, `po`, `ss`, `sb`,
      and any path carrying a `[sub-filter]` (`related-type` and
      `related-target` are separate index rows, so ANDing them also matches
      two different components). A filter that cannot be answered is a 400
      under **any** `Prefer` header: ignoring half a filter returns the
      unfiltered set and tells the client its filter ran.
      `_filter` is therefore no longer in the recognised-but-unsupported list
      that `Prefer: handling=strict` rejects. (`_filterContains` in
      `terminology_handler.dart` is ValueSet expansion filtering, unrelated.)

🛑 **Correcting a quotation that was in both entries above.** They said
`_filter` and `_contained` are "optional in R4" and quoted *"servers are not
obliged to support this parameter"*. **That sentence is not in the spec about
these parameters.** Grepped 2026-08-31: `search.html` uses "not obliged" three
times, about `_include:iterate`, `_summary` and `_elements`, and never about
`_filter`; `search_filter.html` does not contain it at all. What the spec
actually says is broader and does support leaving them unimplemented:
§3.1.1.4.1 *"Servers are not required to implement any of the standard search
parameters (except for the `_id` parameter described above)"*, and §3.1.1.4.13
mentions `_filter` as an alternative "for servers that support this
parameter". Also §3.1.1.4.21 lists `_filter` as a **special** parameter, where
*"The general modifiers and comparators do not apply"* — so `_filter` itself
takes no `:modifier`.
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
- [x] **Only rest-hook and websocket** — closed 2026-09-03: this was never a
      defect, and listing it as open said otherwise. `supportedChannels` is
      `{'rest-hook', 'websocket'}` and `subscription_service.dart:167` refuses
      anything else **at activation**, with `channel.type "<x>" is not
      supported by this server` in `Subscription.error`. Telling a client a
      subscription is active when nothing will ever be delivered is the
      failure worth avoiding, and it is avoided. Implementing email, sms or
      message would mean a mail or SMS gateway, which an on-device server has
      no business holding credentials for.

## Advanced Operations

- [ ] **GraphQL endpoint** — FHIR GraphQL support. Nothing exists.
- [x] **Profile validation** — done 2026-09-02. `$validate` reads `profile`
      from the query string or a `Parameters` body, resolves it against this
      server's own StructureDefinitions, and returns 400 `not-supported` when
      it cannot, which `OperationDefinition/Resource-validate` requires: "if a
      profile is nominated, and the server cannot validate against the
      nominated profile, it SHALL return an error."
      🔴 **It was worse than a missing feature: nothing was validated at all.**
      `FhirValidationEngine` built an empty in-memory cache per call, so every
      request answered "No StructureDefinition found for resourceType: X". The
      one test asserted only `isNot(equals(500))`, so it passed.
      Three fixes made it work, two of them in published packages:
      `fhir_r*_validation` 0.12.0 takes a `resourceCache` and looks the base
      type up by canonical URL rather than bare name; `DbResourceCache` splits
      `url|version`, without which every versioned binding
      (`.../administrative-gender|4.3.0`) missed. Measured end to end: with the
      packaged Patient definition and the packaged value sets in the database,
      `$validate` on a Patient returns **200 with an empty OperationOutcome**,
      offline, no network.
      ⏭️ `mode` (create/update/delete) is still ignored.
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
- [x] **A target with required elements** — closed 2026-09-03. A map that does
      not set `Observation.status`, `Basic.code` or `RelatedPerson.patient`
      cannot be built, and `FhirMapEngine.transformBuilder` reports that by
      **returning an OperationOutcome rather than throwing**. The handler
      returned it with HTTP 200; it returns **422** with the outcome.
      The open half was what the outcome SAID: `build()` is
      `Type.fromJson(toJson())` and `fromJson` dereferences the required
      elements, so the diagnostics read `Null check operator used on a null
      value` — no type, no element, nothing a map author can act on.
      Fixed in `fhir_r4_mapping` on `dev` (`60fd7e5b1`): the build is caught
      separately and reports the target type plus the elements the map did
      produce, which is the list the missing one is absent from.
      ⏭️ fhirant depends on the published 0.12.0, so it still shows the old
      message; `mapping_handler_test.dart` pins that rather than pretending,
      and the assertion flips when the next release lands. Naming the exact
      element at its source would mean changing every generated `fromJson` in
      `fhir_r4`, which this deliberately does not do.
- [x] **A canonical the server does not hold** — closed 2026-09-02, and the
      old entry described what the comment claimed rather than what the code
      did. The fallback returned the URL's last segment whatever it was, so an
      unheld profile produced the target type `us-core-patient`. It is guarded
      now: the last segment is accepted only when it names a real R4 resource
      type, and otherwise the caller gets a 400 naming the canonical.
      🔴 **This bites HL7's own published example.**
      `StructureMap-supplyrequest-transform.json`, in
      `~/.fhir/packages/hl7.fhir.r4b.core#4.3.0/package/`, gives its target as
      `http://hl7.org/fhir/StructureDefinition/supplyrequest` — lower case,
      while the type is `SupplyRequest`, and `R4ResourceType.fromString` is
      case sensitive. Unguarded that produced the type `supplyrequest`. The
      cure is unchanged: POST the StructureDefinition first.
- [x] **Several target structures** — closed 2026-09-02. `structure` is
      `0..*`, structuremap.html gives no rule for choosing among several
      targets, and the operation returns exactly one resource. Targets
      resolving to **different** types are refused with a 400 naming them,
      because picking one would be inventing the rule the spec does not state.
      Targets resolving to the **same** type are unambiguous and allowed.
      Six tests in `mapping_target_test.dart`.

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
- [ ] **Conformance suite** — automated FHIR Touchstone or official test kit
      testing. **Blocked on infrastructure, not on code**: Touchstone calls the
      server from the internet, the Cloud Run deployment was deleted
      2026-07-20, and the touchstone.aegis.net account is Grey's. The 1056/1056
      on record is from 2026-03-17 and has not been re-run since; search,
      `$validate` and `$transform` have all changed materially since.
      **What runs instead, in our control:** `tools/smoke_test.dart` against a
      local server, 35 checks over 8 groups as of 2026-09-02, including
      `_filter`, `_contained`, `$validate` with a profile and `$transform`
      target resolution. Start the server with
      `--dev-mode --spec-path assets/fhir_spec` and an
      `FHIRANT_ENCRYPTION_KEY`; the flag is `--dev-mode`, not `--dev`.

## Deployment

- [x] **Docker** — built and **run** 2026-08-31, not merely present. The build
      context is this repository now: it used to have to be the parent
      directory, for the cicada path dependency that became a git dependency,
      and `git` was added to the build stage so `pub get` can fetch it.
      `dart build cli` produces the native bundle with `libsqlite3mc.so`
      beside it.
      Smoke test through the running container on port 8099, all from the
      HTTP side: `/health` and `/metadata` answer; `POST /Patient` → 201;
      `?family=Okello` → 1; `?family:exact=okello` → 0, which is right,
      `:exact` being case sensitive; `?birthdate=gt1979-01-01` → 1.
      Two things learned by running it. **The image requires auth** — a bare
      request is 401, and `/auth/register` then `/auth/login` gives a token
      that works. **The default rate limit is 10 requests per 60 seconds**, so
      a smoke script hits 429 quickly.
      `$validate` behaves as the tests say: an unheld profile is 400
      `not-supported`, and a plain Patient is 422 naming
      `http://hl7.org/fhir/ValueSet/languages` — the base StructureDefinition
      resolves from the database, and the value set does not, until the
      `fhir_r4_validation` release lands.
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
- [ ] **An export job occasionally never finishes.** One mechanism is proven
      and fixed; the two original occurrences remain untraced.
      **Proven 2026-09-03:** the status endpoint answers **404** for a job that
      was cancelled or whose row is gone, and `pollUntilComplete` treated only
      200 and 500 as terminal. Kick off, DELETE, then poll: 404 on every
      attempt, unbounded, until `dart test`'s 30-second timeout. A 404 now
      fails the test naming the job.
      **Also fixed:** the outer `catch` in `_processExport` calls `_failJob`,
      which is itself a database write. If that write failed too — the database
      closed under it, the row deleted — the exception escaped and the job
      stayed `in_progress` for ever, so every poll answered 202. It is wrapped
      now and logs that the job will stay `in_progress`.
      🛑 **Whether either mechanism caused the 2026-08-29 failure or the
      2026-08-30 clone run is NOT established.** Those two were never traced:
      one occurrence in eight whole-suite runs, on `_typeFilter combined with
      _since` rather than the cancel test, with two immediate reruns in the
      same clone passing 775/775.
      The deadline stays at 20 seconds, under the framework's 30, so a genuine
      hang reports the job, the elapsed budget, the poll count and the last
      `X-Progress` line — `Queued` or `Exporting...` separates a job that never
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
