# Candidates from the reading pass (each to be probed; not findings yet)

## Setup
- S1 CONFIRMED docker build fails from a working checkout (no .dockerignore).
- S2 Dockerfile HEALTHCHECK runs `server --help`, not a request to /health; `|| exit 1` after a JSON array makes it shell form. Probe: docker inspect health after S1 fix.
- S3 bin/server.dart declares `--config` and never reads it; CLAUDE.md lists `--sqlcipher-path`, `--dev` (flag is `--dev-mode`), "pub.dev ^0.7.0", "flutter_lints", "Play Store", `logs` table, "version id = timestamp". Doc drift.
- S4 `--dev-mode` couples two unrelated things: auth off AND the public encryption key allowed. App default is auth off; CLI/Docker default is auth on. One setting, same default, independent of the key.
- S5 `http: any` in fhirant_server pubspec. cicada `ref: main` unpinned (the lock pins it; does the Docker `pub get` enforce the lock?).
- S6 CI does not build the Docker image; actions pinned by tag.
- S7 Timer.periodic hourly callback awaits four DB calls with no try/catch (fhirant_server.dart:772). An exception there is an unhandled async error. Probe: what an unhandled error in a timer callback does to the CLI process.
- S8 stop() closes _requestLogController; a second start on the same FhirAntServer has a dead request log. Check server_service.dart.
- S9 always binds anyIPv4; no loopback-only choice; no IPv6.

## Auth (reviewed with auth ON)
- A3 lockout kills live sessions: middleware refuses a valid token while `locked_until` is in the future, and anyone can lock any known username with 5 wrong passwords (10/min allowed). Unauthenticated session kill and a standing admin lockout.
- A7 patient/ scopes with no patient context: Principal.compartmentFor returns null (unconfined) when patientId is null. authorizeRequest refuses typed paths, but root paths (`GET /?`, `_history`, `POST /_search`) skip that check. Register lets an admin create such an account (scopes patient/*.rs, no patient).
- A15 HEAD requests: methodToPermission returns null for HEAD, so no scope check at all. shelf_router serves HEAD from GET routes.
- A16 first-user bootstrap over the network on CLI/Docker: first POST /auth/register becomes admin.
- A18 login distinguishes deactivated (403) and locked (423) before checking the password: username enumeration; the inactive path skips the decoy hash (timing).
- A19 refresh rotation has no reuse detection; auth code `used` check is not atomic (two concurrent exchanges both succeed); token responses lack Cache-Control: no-store.
- A20 OAuth: an unregistered client_id with any redirect_uri is accepted on first use; the consent page shows the client_id the attacker chose and not the redirect host. Phished login sends the code to the attacker, who holds the PKCE verifier. Also `Uri.replace(queryParameters:)` drops a redirect_uri's own query.
- A21 PBKDF2 120k in pure Dart on the event loop: measure ms per login; blocks every request; unauthenticated. OWASP figure to be read, not recalled.
- A22 Pkce still accepts `plain` (dead but present).
- A25 no password change, no deactivate, no role/scope change endpoint (deactivateUser exists in the DB class, no route).
- A26 login/authorize HTML: no X-Frame-Options / CSP / no-store.
- A27 compartment membership ignores reference_base_url (referenceTargets checks it).

## DB / SQL
- D2 restore over a store holding a HIGHER version of the same resource: resources row replaced by the backup's lower version; later saves upsert history rows by (type,id,version) and silently overwrite local history.
- D4 saveResource catch-all writes `$e` to stderr and returns null.
- D15 restore does not reload CustomSearchParameters.
- F1 rebuildSearchIndex is not one transaction: tables dropped, refilled page by page, indexes created last. A search during `$reindex` reads a partial index with no indexes; a save during it is indexed and then indexed again by the walk (duplicate rows; tables have no key).
- F2 IndexHostServices stub built by string interpolation: `'{"resourceType":"$type","id":"$id"}'`.
- F4 PRAGMAs: journal_mode, synchronous, temp_store, secure_delete, foreign_keys. temp_store matters: are sort spills encrypted under sqlite3mc? Check compile options.
- Q1/Q8 `_text` and `:contains` build LIKE '%word%' from user text; `%` and `_` not escaped (normalize may strip them: check).
- Q3 probe-based planning exists because "this build has no STAT4". Can the sqlite3 hook enable SQLITE_ENABLE_STAT4?
- Q4 two search implementations: the SQL path and the legacy Dart set path (~1,500 lines). Divergences seen by reading: an invalid date/number on the general path is skipped (`continue`) where the SQL path throws 400; `:missing` on the general path reads whole rows incl. JSON; the general-path chain runs one search per reference row; general-path `_has` ignores referenceParam. Probe: the same query down each path.
- Q5 general path "all ids" reads full rows (JSON) to take ids.
- Q6 `:missing=<not true/false>` treated as false.
- Q7 `:identifier=|value` ignores the no-system form; value not unescaped.

## Added while reading the server (2026-09-17, second batch)
- DROPPED F2 (stub JSON interpolation): the regex admits only letters and FHIR id characters.
- DROPPED Q1/Q8 (LIKE wildcards): normalizeSearchString turns all \p{P} into spaces, so % and _ never reach LIKE.
- Q10 dates with no zone are indexed and searched in the DEVICE's local zone (fhir_date.dart). A phone that changes zone: stored [00:00 old zone, +1d) no longer inside the search day in the new zone, so `birthdate=1990-01-15` (eq = containment) stops matching. Probe with TZ env var.
- Q9 modifier table: string allows `:text`, reference allows a literal `:type`; neither is built (fall to the general path and are answered as something else). Read R4B search.html 3.1.1.4.4 whole before writing this up.
- H1 `_contained=true|both` refused with "this server does not index contained resources"; contained resources ARE indexed under `#Type` since fhir_db schema 7. Stale message in resource_handler.dart and search_parser.dart.
- H8 read of a resource outside the compartment is 403 (exists), absent is 404, deleted is 410: existence oracle for a patient token. Low.
- H10/B3 If-None-Exist search has no count (REST and Bundle): hydrates every match.
- H12 PUT accepts any id string; no check against the FHIR id grammar.
- H15/B2 SearchParameter delete needs system authority on DELETE /SearchParameter/id only; conditional delete and a Bundle DELETE entry skip the check.
- B1 Bundle entry urls with more than two segments (`Patient/p/_history`, `Patient/p/$everything`) are processed as `Patient/p`.
- B4 no request body size limit anywhere (`readAsString` on every write route).
- B6 a transaction that saves a SearchParameter and then rolls back leaves it in the in-memory registry.
- B8 Bundle GET entry ignores `_has`, `_include`, `_summary`, `_elements`, `_filter`.
- P1 REST PATCH takes no SubscriptionService: no notification for a patched resource, and a patched Subscription is never re-activated (client can PATCH status to active). Bundle PATCH does both. `$meta-add`/`$meta-delete` also notify nothing.
- E1 `$export` NDJSON files are plaintext on disk for 24 h beside an encrypted database. exportJson already streams from the store: the file route could stream from the store and write nothing.
- E2 `_typeFilter` hydrates every match to take ids (`search`, not `searchIds`), twice.
- C1 `$cql`, `Library/$evaluate`, `$fhirpath`, `$transform` run client-supplied programs on the server isolate with no deadline. One slow expression stops every request. Measure.
- WS1 websocket `bind` accepts any id, unbounded ids per socket, no check the Subscription exists or is a websocket one.
- F1 CONFIRMED BY ITS OWN DOC (reindex_handler.dart:20-23): searches during `$reindex` read a partially filled index with no indexes. Their comment gives 1,000 s for the 929k store. Probe for the wrong answer.
- AU1 AuditEvent is an ordinary resource: any writer can PUT/PATCH/DELETE the trail.
- AU3 failed logins are audited as `anonymous`; the attempted username is not recorded.
- AU4 AuditQueue ignores saveResources' `false`: a failed batch is lost without a log line ("nothing is dropped" is not true).
- AU5 no retention for AuditEvents; every read writes one.
- BK3 the `spec` tag that excludes a resource from `$backup` and system `$export` is client-writable meta.tag: a client that tags a Patient removes it from every backup. Same shape as the DELETED-tag tombstone (2026-09-08 row 36).
- BKC1 envelope `kdf.iterations` is read from the file with no ceiling.
- FC1 🔴 forecast: `_searchForPatient` catches everything and returns []: a failed Immunization read yields a forecast from an empty history (every dose due); failed Condition/Allergy reads drop contraindications. Silent.
- T1 `$validate-code` on a ValueSet never applies compose.exclude (comment at :729 says why it thinks it need not; a code found in an include returns true first).
- T3 a CodeSystem this server does not hold (LOINC, SNOMED) is treated as empty: `$expand` answers 200 with nothing, `$validate-code` answers result=false, `:in` matches nothing and `:not-in` everything. "Cannot say" answered as "no".
- T4 `$translate` returns the first target only.
- V1 CONFIRMED against OperationDefinition/Resource-validate (profiles-resources.ndjson, `comment`, verbatim): "This operation returns a 200 OK whether or not the resource is valid. A 4xx or 5xx error means that the validation itself could not be performed". validate_handler.dart:154 answers 400 for an invalid resource.
- V4 DbResourceCache is rebuilt per `$validate`; getStructureDefinitions/getResourceNames read whole types. Measure.
- M1 CapabilityStatement says conditionalUpdate: true; there is no `PUT /[type]?criteria` route.
- M2 oauth-uris still lists `register` -> /auth/register (user accounts, not client registration).
- M5 CONFIRMED: CapabilityStatement cites OperationDefinition/Practitioner-everything, RelatedPerson-everything, Device-everything; the bundled R4B spec has only Patient-, Encounter-, Group- and MedicinalProductDefinition-everything.
- CN1 content negotiation interpolates the Accept header into a JSON string unescaped; reindex handler hand-escapes JSON.
- ST1 structure: every handler carries its own `_errorResponse`/`_validationErrorResponse`/`_operationOutcome`; count them.
- JP1 JSON Patch `test` compares jsonEncode strings (member order matters); move/copy/test treat JSON null as absent.
