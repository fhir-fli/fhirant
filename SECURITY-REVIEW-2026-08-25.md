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

### F3 — HIGH — The mobile app serves plaintext HTTP only

`FhirAntServer.startHttps` exists (`fhirant_server.dart:509`) and the CLI
exposes `--https`, but the app calls `startHttp` unconditionally
(`server_service.dart:41`) and advertises `http://$ip:$port`
(`server_state.dart:80`), which is what the QR code encodes.

Under this threat model that is the whole record and every bearer token
crossing an ad-hoc disaster-setting WiFi in the clear, readable by anyone
associated to the same access point.

**Recommendation**: the app should generate a self-signed certificate on first
run — `SecureStorageService.generateSelfSignedCertificate` already exists and is
unused — serve HTTPS, and put the certificate fingerprint in the QR payload so
the joining device can pin it. Self-signed with pinning is materially better
here than cleartext, and it needs no CA and no connectivity.

### F4 — HIGH — `$backup` is a plaintext dump, and it is the device-to-device path

`backupHandler` returns a JSON Bundle of the database with no encryption and no
passphrase (`backup_handler.dart:40`), over the cleartext transport of F3.

This is the finding that matters most, because it is where the deployment model
and the security model collide. The database is encrypted at rest with a key
sealed in platform secure storage — which is precisely what stops it moving to
a replacement device. The only supported way to satisfy "the device died, carry
on from another one" is therefore to decrypt everything, ship it in the clear,
and re-encrypt it on the far side. **The at-rest encryption is defeated at
exactly the moment the deployment model needs it most.**

**Recommendation**: a passphrase-wrapped export. Operator supplies a passphrase,
run it through a KDF (PBKDF2 is already in the codebase; Argon2id is better if
a dependency is acceptable), and encrypt the export blob with the derived key.
Then the export is safe to move by any means, including an SD card handed to
someone — which in a disaster setting is more realistic than a network transfer.
It also removes the keystore as a single point of failure: passphrase plus
backup file is sufficient to reconstitute the record, which is what "flexible,
moves between devices" actually requires.

### F5 — MEDIUM-HIGH — Authentication is disabled by default, and dev mode is full admin

`kDefaultAuthDisabled = true` (`security_config.dart`) makes a fresh install
default to Experimentation mode. In that mode `_devModeMiddleware` replaces the
auth middleware entirely and injects a synthetic user with role `admin` and
scope `system/*.*` (`fhirant_server.dart:566-573`) — so every request is
unauthenticated and fully privileged, including `$restore`.

This is deliberate and documented for the pre-release period, and the app shows
a standing warning. It is listed here because it is the shipping default and
nothing has shipped yet: the decision is still free.

**Recommendation**: flip it to `false` before any real deployment. Given that
there are no installs, there is no reason to carry the permissive default
forward.

### F6 — MEDIUM — Plaintext PHI log file sits beside the encrypted database

`FhirantLogging` writes JSON lines to a file in app documents, unencrypted
(`fhirant_logging.dart:45-50`), and the app enables it (`main.dart`, log path
under the documents directory). The request logger writes
`request.requestedUri` — **the full URI including the query string**
(`fhirant_server.dart:628-631`).

So `GET /Patient?name=Faulkenberry&birthdate=1974-12-25` is written verbatim, in
the clear, next to the database whose encryption was the point. `Logger.root.level`
is `Level.ALL`, and error paths log exception messages that may carry resource
content.

**Recommendation**: log the path without the query string, or redact search
parameter values; and either store the log inside the encrypted database or
disable file logging on mobile. The live in-app request log already uses
`requestedUri.path` without the query — the file log should match it.

### F7 — LOW — CORS defaults to `allowOrigin: '*'`

`CorsConfig.allowOrigin` defaults to `*` (`cors_middleware.dart`). Auth is
bearer-token rather than cookie-based, so a browser will not attach credentials
automatically and this is not directly exploitable. It does mean any web page
the operator visits can reach the API on the local network and probe it.

**Recommendation**: default to the app's own origin and require an explicit
opt-in for `*`.

### F8 — LOW — Two public-route prefixes are prefix matches rather than exact

`_publicPrefixes` in `auth_middleware.dart` contains `metadata` and `health`
alongside genuine prefixes like `auth/`. They are matched with `startsWith`, so
any future route beginning with those strings becomes unauthenticated silently.
No current route collides, and FHIR resource types are capitalised, so this is
latent rather than live.

**Recommendation**: exact-match the non-prefix entries.

### F9 — LOW — `x-forwarded-for` is trusted when connection info is absent

`_trustedClientIpMiddleware` overwrites the header from the socket address, so
spoofing is correctly prevented on a real connection. When
`shelf.io.connection_info` is missing it passes the request through unchanged
(`fhirant_server.dart:606-608`), leaving a caller-supplied header to drive
logging and rate limiting. That path is reachable in in-process tests rather
than over a socket.

**Recommendation**: strip the header rather than passing it through.

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
2. F4 with F3 — the passphrase-wrapped export is the piece that makes the
   deployment model coherent, and it reduces how much the transport has to
   carry.
3. F5 — a one-line decision, but take it deliberately.
4. F6 — small and self-contained.
5. F7, F8, F9 — hardening.
