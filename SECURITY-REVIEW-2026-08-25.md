# fhirant security review — 2026-08-25

## Scope and method

Full read of the security-relevant surface of all five packages (~17.4k lines):
the middleware pipeline, auth and scope enforcement, every handler that returns
or accepts patient data, key management, the storage layer, transport, and
logging. Findings below were confirmed by reading the code at the cited
locations, not inferred from names or greps.

F1 and F2 are backed by executable evidence, not by reading alone:
`packages/fhirant_server/test/middleware/scope_enforcement_test.dart` (13 tests)
drives the real auth middleware and records what it does today. The tests
marked BYPASS pass *because the defect is present*; when a finding is fixed the
expectation inverts and the test becomes its regression guard.

That file also corrected me. My first draft of F2 claimed a patient-scoped
token could read another patient's compartment and system-wide history. Both
are refused — the test proves it — and the actual defect turned out to be a
different and subtler one. The claim did not survive being run.

Standards consulted for F6 and F10: ISO 27789:2021 (audit trails for EHRs) and
ASTM E2147-18. Precedent consulted for the F3 follow-up: Syncthing, whose
device ID *is* the SHA-256 fingerprint of a self-signed certificate generated
on first run, with trust resting entirely on comparing that fingerprint — the
same shape as what F3 now builds.

Not covered: the Android/iOS platform configuration (manifest, entitlements,
network security config), dependency CVE audit beyond the discontinued-package
cleanup, and any dynamic/fuzz testing. Those are named as gaps, not silently
omitted.

## Threat model this review assumes

fhirant has never been deployed. There are no installs to migrate, so breaking
changes are free right now — this is the cheapest these fixes will ever be.

- **Adversary**: someone who physically holds the device (lost, stolen, seized,
  or passed on), and anyone on the same local network. Not a state actor with
  forensic extraction hardware.
- **Assets**: the patient database at rest and in transit, and whatever
  credential lets a second device take over the record.
- **Constraints that are not negotiable**: works fully offline; the record must
  survive the primary device dying by moving to another device; operators are
  working in a disaster setting and will take the easy path when the secure one
  is laborious.
- **Accepted risk**: a rooted or jailbroken device is out of scope. The OS
  keystore is trusted to the extent the platform allows.

The recurring theme below is that **the portability requirement and the
at-rest encryption are currently in conflict**, and where they meet, the
encryption loses.

---

## Findings

Severity is relative to the threat model above, not to a generic internet-facing
server.

### F1 — HIGH — ✅ FIXED — Root-level `$` operations bypassed scope enforcement entirely

`SmartScopeEnforcer.resourceTypeFromPath` returns `null` for any path whose
first segment starts with `$` (`smart_scopes.dart:219`). The auth middleware
only performs its scope check when a resource type is resolved
(`auth_middleware.dart`, "Only enforce scopes for resource-targeted requests"),
and the separate privileged-operation gate covers only five names —
`$backup`, `$restore`, `$export`, `$export-poll-status`, `$export-file`
(`smart_scopes.dart:134-140`).

Everything else at the root is therefore authenticated but **unauthorised**:
`$cql`, `$fhirpath`, `$transform`, `$validate`, `$immds-forecast`.

`$fhirpath` is the sharpest: it fetches an arbitrary resource by type and id
straight from the database (`fhirpath_handler.dart:67`) and evaluates an
expression against it. A `readonly` user, or one scoped to a single patient,
can read any resource in the database through it. `$cql` similarly loads
patient data (`cql_handler.dart:437`).

**Fixed**. `isRootDataOperation` treats every root `$` operation as
data-reading unless it appears on an explicit no-data allowlist — currently
`$validate` and `$transform`, both of which work only on what the caller
posted. A new operation added later therefore fails closed instead of
inheriting the old no-check-at-all behaviour.

Data-reading root operations now require `isUnscopedDataAccessAuthorized`: a
`user`/`system` context scope with the `*` resource wildcard and the needed
permission. A `patient/` context is refused outright even with `patient/*.rs`,
because nothing downstream confines the result to that patient — which is F2's
note about latent compartment gaps, closed at the gate rather than left to each
handler.

Which handlers read data was established by reading them, not by guessing:
`$immds-forecast` also calls `getResource` and `search`, so it is gated too.

### F2 — HIGH — ✅ FIXED — An unparseable scope was dropped rather than rejected, so a malformed narrowing scope silently widened access

`SmartScope.parse` accepts only SMART **v2** permission letters — `c r u d s *`
(`smart_scopes.dart:33`). A v1-style scope such as `patient/*.read` fails to
parse and returns null. Every consumer — `isAuthorized`, `hasPatientScopes`,
`isPatientOnlyContext` — then **skips** it and carries on with the scopes that
did parse.

Alone that is fail-closed: a token carrying only unparseable scopes authorises
nothing and is denied. **Mixed, it fails open.** For the token
`['patient/*.read', 'user/*.rs']`, measured:

- `hasPatientScopes` is **false**, so the middleware never demands a patient
  claim;
- `isPatientOnlyContext` is **false**, so `extractPatientContext` returns null
  and `resource_handler` applies no compartment filter;
- `isAuthorized(…, 'Patient', 'r')` is **true**, because the surviving `user/`
  scope still grants the read.

The issuer asked for "this patient, read only". What survives is "any patient,
read and search". The scope that *restricted* access is the one discarded.

**Fixed**. The middleware now calls `allScopesParse` and returns 403 when any
scope in the token fails to parse, rather than acting on the subset that
happened to parse. A scope the server does not understand is not safely
ignorable, because it may be the one doing the narrowing.

Nothing in the existing suite depended on v1 scopes being tolerated: 649 tests
pass, none changed.

Two related notes, both measured rather than assumed:

- Compartment enforcement really is present only in `resource_handler.dart` and
  `patch_handler.dart`; `history_handler`, `compartment_handler`,
  `document_handler`, `meta_handler`, `bundle_handler` and `websocket_handler`
  never call `extractPatientContext`. Checked by opening each file rather than
  by grepping one function name: none references `auth_user`, scopes, or a 403
  path, and none imports `patient_scope.dart` or any auth utility —
  `history_handler` imports only the database, logging, header helpers and
  shelf. Enforcement would need one of those imports or the request context,
  and neither is there. **This is currently masked** — a
  patient-scoped token is stopped earlier by the resource-type and permission
  checks (verified: `GET /_history` and `GET /Patient/patient-B/Observation`
  are both refused for `patient/Observation.read`). So it is latent, not live.
  It becomes live the moment a handler is reached by a token the type check
  admits, which is what F1 already demonstrates.
- Enforcement being per-handler and opt-in is the structural problem behind
  both F1 and F2. The safe shape is one central decision that denies anything
  it does not positively recognise.

### F3 — HIGH — ✅ FIXED — The mobile app served plaintext HTTP only

`FhirAntServer.startHttps` exists (`fhirant_server.dart:509`) and the CLI
exposes `--https`, but the app calls `startHttp` unconditionally
(`server_service.dart:41`) and advertises `http://$ip:$port`
(`server_state.dart:80`), which is what the QR code encodes.

Under this threat model that is the whole record and every bearer token
crossing an ad-hoc disaster-setting WiFi in the clear, readable by anyone
associated to the same access point.

**Fixed**. `ServerService.start` now calls `startHttps` with a TLS identity
from `loadOrCreateTlsIdentity`, and the advertised URL is `https://`.

The identity is generated once and reused. That is the part that matters: the
certificate is self-signed and issued for `localhost`, so a client reaching the
phone at whatever address it has on this network cannot validate it by name and
must pin its fingerprint instead — and regenerating on each start would change
the fingerprint and break every device already paired. Generating an RSA key
pair takes a few seconds on a phone, which is another reason it happens once.

The SHA-256 fingerprint is shown on the dashboard and carried in the QR payload
alongside the URL (`{"url":…,"sha256":…}`), so pairing does not depend on
reading 32 bytes of hex aloud — though an operator can, because it is displayed.
It is computed over the DER bytes, the same convention as `openssl x509
-fingerprint -sha256`; a test pins it against OpenSSL's own output for a real
certificate rather than recomputing it the way the implementation does, because
that would only prove the code agrees with itself.

Still open, deliberately: **no client in this repo consumes that fingerprint
yet.** The server presents a pinnable identity; a joining device has to be
written to check it.

### F4 — HIGH — ✅ FIXED — `$backup` was a plaintext dump, and it is the device-to-device path

`backupHandler` returns a JSON Bundle of the database with no encryption and no
passphrase (`backup_handler.dart:40`), over the cleartext transport of F3.

This is the finding that matters most, because it is where the deployment model
and the security model collide. The database is encrypted at rest with a key
sealed in platform secure storage — which is precisely what stops it moving to
a replacement device. The only supported way to satisfy "the device died, carry
on from another one" is therefore to decrypt everything, ship it in the clear,
and re-encrypt it on the far side. **The at-rest encryption is defeated at
exactly the moment the deployment model needs it most.**

**Fixed**. `$backup` now requires a passphrase and returns an encrypted
envelope: PBKDF2-HMAC-SHA256 at 210,000 iterations (higher than the login
hash's 120,000 — a backup is derived once per export, and the file it protects
may sit on removable media where an attacker can guess at leisure) into
AES-256-GCM, with a fresh salt and nonce per export.

`$restore` takes the envelope with the passphrase in an `X-Backup-Passphrase`
header, and still accepts a plain Bundle so that importing FHIR produced
elsewhere keeps working — refusing that would not make anything safer, since
the caller already holds the data.

The passphrase goes in the request body (backup) or a header (restore), never
the query string, because request URIs are written to the log — see F6.

This is what makes the deployment model coherent: passphrase plus file is
sufficient to reconstitute the record, so the keystore stops being a single
point of failure and the export can travel by any means to hand, including an
SD card — which in a disaster setting is often the only one.

17 tests cover the envelope: round trip including non-ASCII, that no patient
data or passphrase appears in it, that it carries no key material, that a wrong
passphrase and a flipped ciphertext byte and a substituted salt all fail the
authentication tag, and that salt and nonce are never reused across exports.

**The app can now do this.** `BackupCard` on the dashboard exports and
restores directly against the database, so it needs no running server, no
network and no login. The Bundle assembly and restore loop moved out of the
handler into `BackupService`, which both the card and the handler call, so
there is one implementation rather than two.

Choosing a passphrase requires confirmation and twelve characters: a mistyped
passphrase produces a file nobody can ever open, and nothing later can detect
that. Restore asks for a passphrase only when the file is actually an
envelope, since a plain FHIR Bundle from elsewhere still imports. The export
goes to the system share sheet, which is what lets it reach another phone, an
SD card or a laptop; writing to app storage alone would leave it on the device
that is failing.

### F5 — ✅ CLOSED — Auth-off default is a settled decision, not an open item

`kDefaultAuthDisabled = true` (`security_config.dart`) makes a fresh install
default to Experimentation mode. In that mode `_devModeMiddleware` replaces the
auth middleware entirely and injects a synthetic user with role `admin` and
scope `system/*.*` (`fhirant_server.dart:566-573`) — so every request is
unauthenticated and fully privileged, including `$restore`.

This is deliberate and documented for the pre-release period, and the app shows
a standing warning. It is listed here because it is the shipping default and
nothing has shipped yet: the decision is still free.

**Decision (Grey, 2026-08-27): stays `true` for now.** The app is in testing
and authentication off is what makes that testing practical. It is flipped to
`false` before deployment, not before then.

🛑 **This is CLOSED. Do not list it as open, as a decision to make, as
deferred, or as a follow-up. Do not raise it again.** It is a posture that was
chosen, not a defect awaiting a fix. The flip to `false` happens as part of
deployment, by Grey, and belongs to the release checklist rather than to this
review.

### F6 — MEDIUM — ✅ FIXED — Plaintext PHI log file sat beside the encrypted database

`FhirantLogging` writes JSON lines to a file in app documents, unencrypted
(`fhirant_logging.dart:45-50`), and the app enables it (`main.dart`, log path
under the documents directory). The request logger writes
`request.requestedUri` — **the full URI including the query string**
(`fhirant_server.dart:628-631`).

So `GET /Patient?name=Faulkenberry&birthdate=1974-12-25` is written verbatim, in
the clear, next to the database whose encryption was the point. `Logger.root.level`
is `Level.ALL`, and error paths log exception messages that may carry resource
content.

**Confirmed by reading the file, not the code.** A real request driven through
the real pipeline with file logging on wrote, verbatim:

```
{"timestamp":"…","level":"INFO","message":"GET http://localhost:8080/Patient?name=Faulkenberry&birthdate=1974-12-25 - 200 (106ms) from 127.0.0.1"}
```

**Partly fixed.** Query parameter values are redacted before the line is
written, so the same request now logs:

```
{"timestamp":"…","level":"INFO","message":"GET /Patient?name=[redacted]&birthdate=[redacted] - 200 (87ms) from 127.0.0.1"}
```

Parameter names survive on purpose: knowing which search was run is most of the
diagnostic value and identifies nobody. Resource ids in the path also survive,
which is a decision rather than an oversight — they say which record was
touched, and on their own they do not name a person the way a search on name
and birth date does. The regression test pins both halves of that decision.

**Why "partly" — and a correction to how this finding was framed.**

The first version of this finding treated the remaining content as a leak to be
encrypted. That was wrong, and checking the standards rather than reasoning
about it is what showed why.

**ISO 27789:2021 requires** an EHR audit record to uniquely identify the user,
uniquely identify the subject of care, identify the function performed, and
record when it happened. ASTM E2147-18 covers the same ground and adds
retention — as long as the medical record, at minimum ten years. So *that
content is mandatory*, not incidental. The question was never whether to hold
it; it is where it lives and who can read it.

**fhirant already does the compliant thing.** `auditMiddleware` writes FHIR
`AuditEvent` resources — agent, action, recorded, outcome, entity — into the
encrypted database on every auditable request. The audit trail is in the
protected store where it belongs.

Which makes the plaintext file a **duplicate of protected content in an
unprotected place**, and reframes the remaining work: not "encrypt the log",
but "the debug log should not carry what the audit trail already holds
properly". That is a smaller and better-aimed change than encrypting a file or
moving it into the database, and it does not cost the ability to diagnose a
device that will not start — which the earlier framing would have.

**Done.** The logged URI is reduced to its shape — `/Patient/{id}`,
`/Observation/{id}/_history/{vid}` — so the operation, resource type, outcome
and timing survive and the record identity does not.

Writing the test against the file rather than the code found a second channel
the request line alone would have missed: ten call sites in
`resource_handler.dart` logged ids directly, e.g. `Resource of type Patient
with ID patient-12345 not found.` Those now log `{id}` too.

What is still true, and is accepted rather than fixed: the file remains
plaintext and still records usernames, timestamps, client addresses, resource
*types* and terminology codes. That is a debug log doing a debug log's job. The
raw `catch (e)` paths also remain unbounded — whatever a database or parser
exception embeds goes to disk, and that cannot be bounded by inspection, only
by not logging exception detail at all.

### F10 — MEDIUM — ✅ FIXED — The audit trail did not identify the subject of care

Found while checking F6 against the standards rather than while reading for
bugs.

`_entityReference` in `audit_middleware.dart` takes `Type/id` from the request
path, so `GET /Observation/123` records the *Observation* as the audited
entity. For any resource that is not a Patient, the resulting `AuditEvent`
never names the patient the access concerned.

**ISO 27789:2021 requires the audit record to uniquely identify the subject of
care.** As it stands, fhirant's audit trail satisfies that only for direct
Patient reads. "Who looked at this patient's record" — the question an audit
trail exists to answer — cannot be answered from it for observations,
conditions, medications or anything else.

`agent.who` is also a display string (`{'display': username}`) rather than an
identifying reference, and there is no `agent.network` recording the client
address, which IHE ATNA and ASTM E2147 both expect.

**Related, found while answering a question about what `$fhirpath` does**:
`fhirpath_handler.dart:138` carries `// TODO(fhirant): Add audit log entry for
PHI access`. That operation reads a resource straight out of the database by
type and id and deliberately writes no AuditEvent. Together with F1 — which
let any account reach it — it was the sharpest hole in the server: read any
record, leave no trace. F1 closed the access half; this is the trace half, and
it belongs with this finding rather than as a separate TODO.

**Fixed.** The audit middleware resolves the resource to its patient and
carries that patient as a second `AuditEvent.entity` with the Patient role. R4
has no `AuditEvent.patient` element — the `patient` search parameter is defined
over `agent.who` and `entity.what` — so an entity is where it belongs. A read of
a Patient adds nothing extra, because the resource entity already is the
subject and a duplicate would make one access look like two.

The resolution is `FhirDao.subjectOfCare`, added to `fhir_r4_db`, `fhir_r5_db`
and `fhir_r6_db`. It reads the reference search index, which is already
populated at save time, so the answer costs one indexed row read rather than
deserializing the resource. `FhirAntDb` carries its own copy because
`fhirant_db` resolves `fhir_r4_db` from pub.dev at 0.8.0; the inherited version
arrives with the next release.

It is deliberately narrow: only `patient` and `subject` count. A `performer` or
`recorder` is a participant, not the subject of care, and naming one would
answer "who accessed this person's record" with someone merely mentioned in it
— worse in a legal record than answering nothing. A resource that names no
patient records none.

`agent.network` now carries the client address, taken from the socket by the
trusted-client-IP middleware rather than from a caller-supplied header.

The `$fhirpath` half is closed too. The path is `/$fhirpath` for every call, so
the middleware could not tell which record was disclosed; the handler now
declares what it read through the response context, which is shelf's route for
handler-to-middleware data. Only the database read is declared — a resource
posted in the request body came from the caller and was never disclosed by the
server, so recording it would put a disclosure in the trail that did not
happen.

`agent.who` now identifies the account, not only names it. A display name is
not an identifier: two clinicians who share a name were indistinguishable in a
record kept for legal purposes. This needed no Practitioner resources — FHIR
lets a `Reference` identify by `identifier` with no resource existing, and the
JWT already carried `userId` beside `username` — so `who` carries
`{system: 'urn:fhirant:users', value: userId}` alongside the display name.

Tests run the whole pipeline against a real database, because what matters is
the AuditEvent that lands in the store, not that a method was called. Every
assertion was watched to fail with the change backed out.

### F11 — MEDIUM — ✅ FIXED — Every resource save committed its own transaction, so bulk writes were slow and Bundle atomicity was manual

Found by measurement, after asserting without it that fanning out AuditEvents
would be "a volume decision on a phone" and being asked to prove it.

Measured on this machine, file-backed SQLite, steady state after warm-up:

| | time | per resource |
|---|---|---|
| 50 `saveResource` calls, sequential | 3584 ms | 71.7 ms |
| the same 50 inside one transaction | 109 ms | 2.2 ms |

**33x.** SQLite is not slow and the search-parameter indexing is not the
problem: the cost is one commit — one flush to storage — per `saveResource`
call.

Neither `bundle_handler.dart` nor `$restore` batches. Extrapolating from the
measured per-resource cost (arithmetic, not measurement): a 100-entry
transaction Bundle costs about 7 seconds, and restoring a 5,000-resource
backup about 6 minutes. The second matters most — restoring onto a replacement
device is the recovery path the whole deployment model rests on.

There is a correctness edge as well as a speed one. FHIR requires a
`transaction` Bundle to be all-or-nothing. Without a database transaction,
`bundle_handler` achieves that by **manual compensating rollback** — re-saving
`previousResource` on failure (lines 629, 646). That rollback can itself fail
partway, leaving a state a real transaction would have made impossible.

**Fixed** for Bundle processing and `$restore`. F10 landed without needing to
fan out AuditEvents — it resolves the subject with one indexed read per
request, so there is no batch of audit writes to join the transaction.

A `transaction` Bundle now runs inside one database transaction and a failure
rolls it back. The 48 lines of manual compensating rollback are gone — with
them the log lines that wrote `Type/id` into the debug file.

`batch` keeps its own semantics: entries are independent requests that share an
envelope, so per-entry failures are caught inside the shared transaction and
the successful siblings still commit. Sharing a transaction for speed must not
quietly turn a batch into all-or-nothing, and a test pins that.

`$restore` batches the same way and keeps per-entry error reporting: an
all-or-nothing import would turn one bad entry into no record at all.

**Verified against a real database, because atomicity is not observable
against a mock** — a mock can show a rollback was *called*; only a database can
show the row is gone. `integration/bundle_atomicity_test.dart` drives the full
pipeline over SQLite and checks the rows afterwards.

**The test was A/B'd rather than assumed meaningful.** With the database
transaction removed, `Patient/keep-1` — written by an entry *before* the
failure — survives the failed Bundle, so entries really are written before the
abort and the assertion is not vacuous. Restored, it is gone.

One thing that A/B does *not* show, and is not claimed: whether the old manual
rollback would have cleaned up this particular case. It probably would have —
a create-via-PUT was the case it handled best. The objection to it was
structural rather than empirical: compensating writes can fail, and the code
logged that possibility.

### F7 — LOW — ✅ FIXED — CORS defaulted to `allowOrigin: '*'`

`CorsConfig.allowOrigin` defaults to `*` (`cors_middleware.dart`). Auth is
bearer-token rather than cookie-based, so a browser will not attach credentials
automatically and this is not directly exploitable. It does mean any web page
the operator visits can reach the API on the local network and probe it.

**Fixed**. `allowOrigin` is now nullable and defaults to null, which publishes
no cross-origin policy at all; `*` remains available as an explicit choice.

CORS is a browser rule, not access control — a non-browser client is
unaffected, so device-to-device use does not change. What the old default gave
away was narrower than it looks: authentication is by bearer token rather than
cookie, so a wide-open policy does not leak authenticated data on its own. What
it did allow is any page the operator visits using their browser to reach this
server on their local network — which the page's author cannot reach directly —
and read the responses. Publishing nothing closes that; a browser SMART app is
now a decision an operator makes rather than a default they inherit.

### F8 — LOW — ✅ FIXED — Two public-route prefixes were prefix matches rather than exact

`_publicPrefixes` in `auth_middleware.dart` contains `metadata` and `health`
alongside genuine prefixes like `auth/`. They are matched with `startsWith`, so
any future route beginning with those strings becomes unauthenticated silently.
No current route collides, and FHIR resource types are capitalised, so this is
latent rather than live.

**Fixed**. `_publicPrefixes` now holds only genuine subtree prefixes (`auth/`,
`.well-known/`); `metadata`, `favicon.ico` and `health` moved to a
`_publicPaths` set matched exactly.

### F9 — LOW — ✅ FIXED — `x-forwarded-for` was trusted when connection info is absent

`_trustedClientIpMiddleware` overwrites the header from the socket address, so
spoofing is correctly prevented on a real connection. When
`shelf.io.connection_info` is missing it passes the request through unchanged
(`fhirant_server.dart:606-608`), leaving a caller-supplied header to drive
logging and rate limiting. That path is reachable in in-process tests rather
than over a socket.

**Fixed — but not the way the recommendation said, because the recommendation
was wrong.** Stripping the header crashes the rate limiter: it casts
`shelf.io.connection_info` unconditionally and falls back to the header, so
removing it turns a trust problem into a `type 'Null' is not a subtype of type
'HttpConnectionInfo'` on every request. That was measured — the change broke 88
tests before it was corrected.

The header is now overwritten with the sentinel `unknown` instead. Every
request arriving without connection info shares one rate-limit bucket, which
throttles them together rather than letting a caller choose their own bucket by
picking a value.

---

## Fixed during this review

Both were found while tracing the discontinued-dependency cleanup, and are
already committed (`6171671`):

- **The SQLCipher key for the patient database was not random** — it was
  `microsecondsSinceEpoch + Object().hashCode`. Now `Random.secure`, 32 bytes.
- **`generateSecureRandomKey` was modulo-biased**: a byte 0-255 taken modulo a
  62-character alphabet, measured at 1.234x over-representation of `A`-`H`. Now
  rejection sampling, with a regression test verified by watching it fail
  against the old code.

`fhirant_secure_storage` had no tests at all, which is why neither was caught.
It has 7 now.

## What is already right

Worth recording so it does not get "hardened" into something worse:

- **Password hashing** is PBKDF2-HMAC-SHA256, 120,000 iterations, 32-byte random
  salt, self-describing format (`password_hasher.dart`).
- **JWT algorithm is pinned** to HS256 rather than trusted from the token
  header, which closes `alg: none` and HMAC/RSA confusion (`jwt_service.dart:9`).
- **Client IP is taken from the socket**, not a caller header (F9 aside).
- **Export file serving validates both path segments** — job id against a
  pattern and file name against traversal (`export_handler.dart:247-251`).
- **Privileged root operations are gated** on admin or an explicit `system/`
  scope, so `$backup`/`$restore`/`$export` are not reachable by a readonly
  account (`auth_middleware.dart`). F1 is that the list is too short, not that
  the mechanism is wrong.
- **Tokens are checked against a revocation list** on every request, hashed
  rather than stored raw (`token_hasher.dart`).

## Suggested order of work

1. ~~F1 and F2~~ — **done**. They were the same defect wearing two hats:
   authorisation decided per handler instead of centrally, failing open when a
   path did not match a known shape. Both now decided centrally and
   deny-by-default, with `scope_enforcement_test.dart` inverted from evidence into
   17 regression guards.
2. ~~F4 with F3~~ — **done**. The passphrase-wrapped export and TLS with a
   pinnable identity. One follow-up left: no client pins the
   fingerprint yet. That is work for whatever device joins, not for this
   server, which already presents a pinnable identity and shows the
   fingerprint with a pairing QR. The backup UI now exists.
3. ~~F5~~ — **closed**. Settled: off through testing, flipped at deployment.
   Not an open item.
4. ~~F6~~ — **done**. Query values redacted and path identifiers reduced to
   shape, so the debug log no longer duplicates what the AuditEvent trail holds
   in the encrypted database.
5. ~~F10~~ — **done**. The trail names the subject of care, records the client
   address, and `$fhirpath` no longer reads a record without leaving a trace.
   `agent.who` now carries an identifier too.
6. ~~F11~~ — **done** for Bundle and `$restore`.
5. ~~F7, F8, F9~~ — **done**.
