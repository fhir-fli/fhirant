#!/usr/bin/env python3
"""Writes asvs_walk.tsv: every one of the 345 OWASP ASVS 5.0.0 requirements
with the fifth review's verdict and where the evidence is. A requirement's
verdict comes from OVERRIDES when it has one, else from its section's entry
in SECTIONS; the script refuses to run if any section is missing, so no
requirement goes unclassified.

Verdicts: PASS (probed, holds), FINDING (probed, fails: report id), N/A (the
requirement's subject does not exist in fhirant, reason given), DOC (a
documentation requirement: not probed; whether the document exists is
stated), NOTPROBED (applies, not measured in this review: said so).

Run: python3 -I tool/review_2026-10-17/asvs_walk.py <asvs-5.0.0.json>
The JSON is OWASP's release file:
https://github.com/OWASP/ASVS/releases/download/v5.0.0_release/
OWASP_Application_Security_Verification_Standard_5.0.0_en.json
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

SECTIONS = {
    'V1.1': ('NOTPROBED', 'canonical decoding/escaping order is a code '
             'property; probed instead through its effects (V1.2, V5.3)'),
    'V1.2': ('PASS', 'asvs_probes V1.2.x: 13 SQL-injection shapes, no '
             'effect; authorize pages escape input'),
    'V1.3': ('PASS', 'asvs_probes V1.3.x: no outbound fetch of client URLs; '
             'regex in $fhirpath killed at 10 s'),
    'V1.4': ('N/A', 'Dart is memory-safe; no unmanaged code in fhirant '
             '(sqlite3/SQLCipher native library aside)'),
    'V1.5': ('PASS', 'JSON only (no XML parser reachable); deep JSON 400'),
    'V2.1': ('DOC', 'no input-validation document; validation is the FHIR '
             'spec + profiles'),
    'V2.2': ('FINDING', 'H3: a required-binding code (Observation.status) '
             'is accepted and stored'),
    'V2.3': ('PASS', 'transactions atomic (http_followups); H5 overlap is '
             'the exception'),
    'V2.4': ('PASS', 'general limiter 600/60 s, credential limiter 10/60 s '
             '(asvs_probes V15.3.4)'),
    'V3.1': ('DOC', 'no browser-feature document'),
    'V3.2': ('PASS', 'API answers fhir+json with nosniff; Binary never served '
             'as text/html (security_probes)'),
    'V3.3': ('N/A', 'no cookies: bearer tokens only (no Set-Cookie in lib)'),
    'V3.4': ('FINDING', 'no Strict-Transport-Security under --https '
             '(tls_probe.txt); CSP with frame-ancestors none on the auth '
             'HTML pages (PASS); nosniff on API responses (PASS)'),
    'V3.5': ('PASS', 'every state change needs a bearer header, which a '
             'cross-site form cannot send'),
    'V3.6': ('N/A', 'the auth pages load no external assets'),
    'V3.7': ('NOTPROBED', 'redirects go only to the client redirect_uri; '
             'M1 lets a first use pin any value'),
    'V4.1': ('FINDING', 'S2 x-powered-by; plain-text 404 "Route not found" '
             'without charset; unknown methods 404 (PASS)'),
    'V4.2': ('NOTPROBED', 'request smuggling: dart:io HTTP/1.1 parser, not '
             'probed'),
    'V4.3': ('N/A', 'no GraphQL'),
    'V4.4': ('FINDING', 'SB1 websocket binds any subscription id; WSS only '
             'when --https'),
    'V5.1': ('DOC', 'limits documented in CLAUDE.md (16 MiB body)'),
    'V5.2': ('PASS', '17 MiB -> 413; deep JSON 400'),
    'V5.3': ('PASS', 'export file/job path traversal refused (9 shapes)'),
    'V5.4': ('NOTPROBED', 'export download Content-Disposition not checked; '
             'no antivirus'),
    'V6.1': ('DOC', 'lockout and limiter documented in CLAUDE.md'),
    'V6.2': ('FINDING', 'P1: common-password list holds 20 entries (ASVS '
             'V6.2.4: top 3000); length 12-128, no composition rules, no '
             'truncation (PASS)'),
    'V6.3': ('PASS', 'brute force limited; enumeration timing 275 vs 350 ms '
             'median of 6 (noisy, L3)'),
    'V6.4': ('NOTPROBED', 'admin sets and knows initial/reset passwords '
             '(V6.4.6 L3 asks otherwise)'),
    'V6.5': ('N/A', 'no MFA'),
    'V6.6': ('N/A', 'no out-of-band authentication'),
    'V6.7': ('N/A', 'no cryptographic authenticators'),
    'V6.8': ('N/A', 'no external identity provider'),
    'V7.1': ('DOC', 'lifetimes documented in CLAUDE.md (8 h access, 7 d '
             'refresh)'),
    'V7.2': ('FINDING', 'T1: two sessions in one second are the same token'),
    'V7.3': ('FINDING', 'no inactivity timeout; R1: refresh has no absolute '
             'lifetime'),
    'V7.4': ('PASS', 'logout, deactivation, password/role/scope change end '
             'sessions (access grid)'),
    'V7.5': ('NOTPROBED', 'no list of active sessions for a user'),
    'V7.6': ('N/A', 'no federation'),
    'V8.1': ('DOC', 'route_scope_table_test pins the rules per route'),
    'V8.2': ('FINDING', 'S1: chain/_has reach types the scopes do not cover'),
    'V8.3': ('PASS', 'decided server-side per request; account re-read each '
             'request'),
    'V8.4': ('N/A', 'single tenant'),
    'V9.1': ('PASS', 'alg none / HS384 / HS512 / RS256 header refused; jwk '
             'header ignored'),
    'V9.2': ('FINDING', 'token with no exp accepted (needs the secret); no '
             'aud claim'),
    'V10.1': ('N/A', 'client-side requirements'),
    'V10.2': ('N/A', 'client-side requirements'),
    'V10.3': ('NOTPROBED', 'no aud in the token; one resource server'),
    'V10.4': ('FINDING', 'M1 redirect pinned on first use without '
              'validation; R1 refresh no absolute cap; code single-use + '
              'revoke, PKCE S256, 5 min code (PASS)'),
    'V10.5': ('N/A', 'OIDC client requirements'),
    'V10.6': ('N/A', 'not an OpenID Provider (openid scope passes through, '
              'no id_token)'),
    'V10.7': ('NOTPROBED', 'authorize issues a code on credentials without a '
              'consent screen'),
    'V11.1': ('DOC', 'no key-management policy document'),
    'V11.2': ('PASS', 'library crypto (Argon2id, PBKDF2-SHA256, SQLCipher, '
              'HS256)'),
    'V11.3': ('NOTPROBED', 'cipher modes of the backup and export file '
              'formats not re-audited here'),
    'V11.4': ('PASS', 'Argon2id passwords; SHA-256 token hashes'),
    'V11.5': ('FINDING', 'auth code / job id are UUID v4 from CryptoRNG: 122 '
              'bits (ASVS L2 asks 128, says UUIDs do not count)'),
    'V11.6': ('N/A', 'no public-key crypto in fhirant'),
    'V11.7': ('N/A', 'L3 memory encryption'),
    'V12.1': ('FINDING', 'tls_probe.txt: TLS 1.0/1.1 refused, 1.2/1.3 '
              'accepted (PASS); TLS 1.2 still negotiates non-forward-secret '
              'AES128-SHA / AES256-SHA (dart:io defaults; no cipher-list '
              'API in SecurityContext)'),
    'V12.2': ('NOTPROBED', 'deployment property: plain HTTP by default'),
    'V12.3': ('NOTPROBED', 'rest-hook delivery uses whatever scheme the admin '
              'gave (http accepted)'),
    'V13.1': ('DOC', 'outbound: rest-hook only (admin)'),
    'V13.2': ('FINDING', 'rest-hook endpoint: no allow-list beyond admin-only; '
              'file:// ftp:// accepted active'),
    'V13.3': ('NOTPROBED', 'secrets from env or a generated file beside the '
              'DB'),
    'V13.4': ('FINDING', 'S2 x-powered-by; TRACE refused (PASS)'),
    'V14.1': ('DOC', 'DB and export files encrypted at rest (checked: FHXP '
              'header); file modes follow umask (0644)'),
    'V14.2': ('FINDING', 'C1: no Cache-Control: no-store on PHI responses'),
    'V14.3': ('FINDING', 'C1 (same)'),
    'V15.1': ('DOC', 'no SBOM / remediation timeframe document'),
    'V15.2': ('PASS', 'osv_check.tsv: 159 locked package versions, 0 OSV '
              'advisories (control jose 0.3.2 found)'),
    'V15.3': ('PASS', 'X-Forwarded-For overwritten; server-owned '
              'Subscription extensions not settable by a patient token'),
    'V15.4': ('NOTPROBED', 'concurrency (L3) not probed'),
    'V16.1': ('DOC', 'logging described in CLAUDE.md'),
    'V16.2': ('PASS', 'JSON log lines with timestamp; no passwords or tokens '
              'in the log'),
    'V16.3': ('PASS', 'refusals audited (AuditEvent), per CLAUDE.md and '
              'grid'),
    'V16.4': ('PASS', 'log injection: 0 forged lines, all lines parse'),
    'V16.5': ('PASS', 'unexpected errors answer a generic OperationOutcome; '
              'G2 forecast 500 is the client-input exception'),
    'V17.1': ('N/A', 'no WebRTC'),
    'V17.2': ('N/A', 'no WebRTC'),
    'V17.3': ('N/A', 'no WebRTC'),
}

OVERRIDES = {
    # The 31 rows left NOTPROBED, measured 2026-11-21 (asvs_notprobed.py ->
    # asvs_notprobed.tsv against the CLI built by `dart build cli`; code
    # reads name their file).
    'V1.1.1': ('PASS', 'asvs_notprobed: family:exact=%2541 finds "%41" '
               'only and =%41 finds "A" only; GET /Patient/%2541 is 404, '
               'not Patient/A: decoded once'),
    'V1.1.2': ('PASS', 'asvs_notprobed: client_id <b>"x&\' escaped once '
               '(no &amp;lt;) on the authorize page; HTML escaped where the '
               'template is built (_escapeHtml), SQL by bound variables '
               '(V1.2.4), JSON by jsonEncode'),
    'V3.7.1': ('PASS', 'the authorize page has no object, embed, applet or '
               'script (asvs_notprobed)'),
    'V3.7.2': ('FINDING', 'M1: a second redirect_uri for a known client is '
               '400 with no redirect (PASS), but a new client_id pins any '
               'host on first use: http://evil.example/cb got the code '
               '(asvs_notprobed)'),
    'V3.7.3': ('FINDING', 'L3: posting credentials answers 302 straight to '
               "the client's redirect_uri, with no notice of the host or "
               'way to cancel (asvs_notprobed)'),
    'V3.7.4': ('N/A', 'L3: fhirant has no domain of its own; a '
               "deployment's operator owns its domain and any HSTS preload "
               '(and no HSTS header is sent: V3.4)'),
    'V3.7.5': ('DOC', 'L3: no document says what happens on a browser '
               'without the expected features; the only browser page is '
               'the authorize form'),
    'V6.2.12': ('FINDING', 'checked against 30,407 common passwords from '
                'SecLists (common_passwords.g.dart), not a breach corpus: of '
                '13 candidates of policy length found in Have I Been Pwned, '
                '11 refused, Summer2024!! (936) and Welcome2024! (6,590) '
                'accepted (asvs_notprobed)'),
    'V7.5.1': ('PASS', 'changing one\'s own password needs the current one: '
               '400 without it, 401 when wrong (asvs_notprobed); there is '
               'no email, phone, MFA or recovery attribute'),
    'V7.5.2': ('FINDING', 'no route lists a user\'s sessions (route table; '
               '/auth/sessions and the like fall through to the FHIR routes, '
               '400). Ending them: logout ends one, a password change all '
               '(V7.4); none needs re-authentication'),
    'V7.5.3': ('FINDING', 'L3: $backup (the whole record) and making an '
               'account admin take the bearer token alone, 200 '
               '(asvs_notprobed)'),
    'V9.2.3': ('FINDING', 'since 2026-11-21 a token carries aud (and iss) '
               'only when the server is started with --base-url (W: aud is '
               'its URL, PASS; another iss/aud with the shared secret 401). '
               'Without it (X, Y, the phone) there is no aud; the token '
               'names its account by the account key (sub), so X\'s admin '
               'token on Y is 401 (asvs_notprobed). Before: exp gen iat jti '
               'role scope userId username, and X\'s admin token worked on Y '
               '(200)'),
    'V10.3.1': ('FINDING', 'as V9.2.3: aud only with --base-url'),
    'V10.3.2': ('PASS', 'scope user/Observation.rs: GET /Patient 403, GET '
                '/Observation 200 (asvs_notprobed; access grid)'),
    'V10.3.3': ('PASS', 'since 2026-11-21 the token names its account by '
                'sub, the account\'s random key, which a backup carries; the '
                'role and patient come from the account. With a shared '
                'secret: nora (not in the backup) 401 on Y; cara, restored '
                'to Y as id 32, 403 on /admin/users (Y\'s role for her), and '
                'unchanged when y-cara, Y\'s id 16, is deactivated, 401 when '
                'cara is (asvs_notprobed). Before: the numeric userId and the '
                'token\'s role, so cara\'s X token opened /admin/users on Y '
                'as Y\'s id 16, a clinician (200)'),
    'V10.3.4': ('N/A', 'the resource server requires no authentication '
                'strength, method or recentness (password only; no acr, '
                'amr or auth_time)'),
    'V10.3.5': ('FINDING', 'L3: no DPoP or mutual TLS; one token answered '
                'from two client addresses (asvs_notprobed)'),
    'V10.7.1': ('FINDING', 'the HTML authorize page names the client and '
                'the scopes before every code, but client identity is not '
                'assured (any client_id, redirect pinned on first use), and '
                'the JSON authorize issues a code to whoever holds the '
                "password, with no page shown (200, asvs_notprobed)"),
    'V10.7.2': ('FINDING', 'the page shows the client_id and the requested '
                'scopes as raw strings (patient/*.cruds), not the scopes '
                'granted (the intersection with the account) or how long '
                'they last (asvs_notprobed)'),
    'V10.7.3': ('FINDING', 'no route to review, change or revoke a grant; '
                '/auth/revoke ends a token, not the grant'),
    'V12.2.1': ('FINDING', 'plain HTTP on every interface by default '
                '(InternetAddress.anyIPv4, fhirant_server.dart); /health '
                "answered 200 over HTTP on this host's LAN address; TLS only "
                'with --https; the phone serves HTTPS'),
    'V12.2.2': ('FINDING', 'CLI: --https takes whatever certificate the '
                'operator gives, unchecked; the phone serves a self-signed '
                'certificate for localhost and shows its fingerprint for '
                'pinning (fhirant server_service.dart, server_state.dart)'),
    'V12.3.1': ('FINDING', 'a rest-hook to http:// is accepted active and '
                'notified in clear; $sync to an http peer sent its request '
                '(with the bearer token given) in clear (asvs_notprobed)'),
    'V12.3.2': ('PASS', 'a self-signed https rest-hook was not delivered '
                '(CERTIFICATE_VERIFY_FAILED, Subscription to error) and '
                '$sync to a self-signed https peer sent nothing '
                '(asvs_notprobed); no badCertificateCallback in the server '
                '(the app sets one only for its own loopback health check)'),
    'V12.3.3': ('FINDING', 'as V12.3.1: server-to-server $sync and '
                'rest-hooks may use plain HTTP'),
    'V12.3.4': ('FINDING', 'no way to trust a specific internal CA or '
                'self-signed certificate for $sync or rest-hooks: the '
                "platform's trust store only (no option in cli/options.dart)"),
    'V12.3.5': ('FINDING', 'L3: $sync authenticates the peer by its TLS '
                'certificate and itself by a bearer token; no TLS client '
                'authentication'),
    'V13.3.1': ('FINDING', 'CLI: the database key from FHIRANT_ENCRYPTION_KEY '
                'and the JWT secret from FHIRANT_JWT_SECRET or a generated '
                '.jwt_secret beside the store; no secrets manager. The '
                'phone keeps both in platform secure storage '
                '(flutter_secure_storage). None in the source'),
    'V13.3.2': ('PASS', 'the generated .jwt_secret is 0600; the environment '
                "of the server process is 0400 (owner only). The store's "
                'files are 0644 and its directory 0775 (umask), encrypted '
                '(asvs_notprobed)'),
    'V13.3.3': ('FINDING', 'L3: SQLCipher and HMAC run in the server '
                'process; no HSM or vault'),
    'V13.3.4': ('FINDING', 'L3: neither secret expires or rotates: fhirant '
                'never calls a database rekey (fhir_db has one), and a new '
                'JWT secret ends every session; no document sets a period'),
    'V1.2.4': ('PASS', 'asvs_probes: values, names, _sort, chains, _has'),
    'V1.3.6': ('PASS', 'no outbound request to 7 client-named URLs'),
    'V2.4.1': ('PASS', 'limiter counts the socket address'),
    'V6.2.4': ('FINDING', 'P1: 20 common passwords, not 3000'),
    'V7.3.1': ('FINDING', 'no inactivity timeout'),
    'V10.4.8': ('FINDING', 'R1: each rotation grants a fresh 7 days'),
    'V9.2.1': ('PASS', 'fixed 2026-11-10: a token without exp is refused '
               '(jwt_service_test; asvs_probes "no exp" 401)'),
    # Measured after the review, 2026-10-21 (REVIEW-2026-10-17, "The
    # NOTPROBED rows, measured after the review").
    'V11.3.1': ('PASS', 'code read 2026-10-21: both file formats are '
                'AES-256-GCM (pointycastle); no ECB, no padding'),
    'V11.3.2': ('PASS', 'code read 2026-10-21: AES-256-GCM'),
    'V11.3.3': ('PASS', 'GCM 128-bit tag; export_file_crypto_test refuses a '
                'changed byte, a cut file, reordered frames, the wrong key'),
    'V11.3.4': ('FINDING', 'export: one job key, one file per type, random '
                '64-bit nonce fixed field (neither SP 800-38D 8.2.1 nor '
                '8.2.2), counter wrapped at 2^32; fixed #79. Backup: fresh '
                'salt, so fresh key, per file'),
    'V11.3.5': ('PASS', 'GCM is an approved AEAD mode; no separate '
                'cipher+MAC pairing exists'),
    'V5.4.1': ('FINDING', '$export-file sent no Content-Disposition and '
               'checked the name only for .. and /; fixed #80 (name must be '
               '<type>.ndjson). $backup already sends one'),
    'V5.4.2': ('FINDING', 'fixed #80: the one served name is letters plus '
               '.ndjson, a plain RFC 6266 quoted-string'),
    'V5.4.3': ('FINDING', 'client Binary and Attachment data were stored '
               'and served (as base64 in FHIR JSON, never raw) unscanned. '
               'Fixed #90 for the CLI/Docker server: every base64Binary in a '
               'stored resource goes to clamd first (422 on a match, 503 if '
               'clamd cannot answer); EICAR refused through the real '
               'clamav/clamav:1.5.4 (test_docker.sh). $restore scanned too '
               '(branch restore-clamd-scan): both formats, every stored '
               'resource before anything is written; 31.8-32.8 s added on '
               'the 928,935-resource MIMIC backup (restore_screen_cost.tsv). '
               'Still open: the phone, which has no scanner'),
    # V5.2's section verdict (body limit) had been inherited by every row;
    # it answers V5.2.1 only. Re-read 2026-10-21.
    'V5.2.2': ('FINDING', 'no file was checked against its declared type. '
               'Fixed #92: Binary/Attachment/Signature data must match its '
               'contentType/sigFormat (WHATWG MIME Sniffing patterns, UTF-8 '
               'text, JSON/XML parse) from a 14-type list; HTML, XHTML, '
               'office files and archives refused; undeclared values judged '
               'by their bytes; on the phone too. 44 of the 57 files in the '
               'published examples pass; the 13 refused are 11 placeholders '
               '("Hello" as a PDF), image/jpg (not an IANA type) and one '
               'XHTML (file_type_examples.tsv)'),
    'V5.2.3': ('N/A', 'no compressed file is accepted (zip and undeclared '
               'archives refused by the V5.2.2 check) and the server '
               'decompresses nothing (no gzip/zlib in lib or bin)'),
    'V5.2.4': ('FINDING', 'L3, met another way 2026-11-02: a per-user '
               'quota does not fit a shared record (Grey); writes are '
               'refused 507 below min(5%, 500 MiB) free plus room to export '
               'every current resource (storage_floor.dart; '
               'every_route_meets_the_storage_floor_test.dart)'),
    'V5.2.5': ('N/A', 'no compressed file is accepted (see V5.2.3)'),
    'V6.4.1': ('FINDING', 'fixed 2026-11-09: an administrator chose a new '
               "account's password and the user kept it; now the account "
               'gets a password nobody holds and waits 12 h for its owner, '
               'who sets their own; an administrator approves it with an '
               '8-letter code (RFC 8628 alphabet), one try per code '
               '(owner_claim_test.dart)'),
    'V6.4.2': ('PASS', 'no hints or secret questions: the users table has '
               'no such column (fhirant_db users schema)'),
    'V6.4.3': ('PASS', "the only reset is an administrator's, which hands "
               'no secret: the owner sets their own password and the '
               'administrator approves it by code; there is no MFA to '
               'bypass'),
    'V6.4.4': ('N/A', 'no multi-factor authentication'),
    'V6.4.5': ('N/A', 'passwords do not expire; the 12 h wait for the owner '
               'is not renewed, a new reset replaces it, and its end is in '
               'the reply (awaiting_owner_until)'),
    'V6.4.6': ('FINDING', 'L3, fixed 2026-11-09 for an honest administrator: '
               'it neither chooses nor is handed any secret (every string it '
               'is handed is checked against the stored hashes, '
               'owner_claim_test.dart). Accepted, not stopped (Grey, '
               '2026-11-09, phone with no outside channel): an administrator '
               'who files a claim itself and approves its own code; both '
               'steps are audited'),
    'V5.2.6': ('FINDING', 'L3, fixed 2026-11-01: a PNG, JPEG or GIF over '
               'maxImagePixels (89,478,485, Pillow MAX_IMAGE_PIXELS) or whose '
               'header gives no size is 422 (file_type.dart, headers only; '
               'file_type_test.dart, pixel_limit/)'),
    # V15.4, measured 2026-10-21.
    'V15.4.1': ('PASS', 'code read: three isolates (program_sandbox, '
                'password_hasher Isolate.run, the app store '
                'createInBackground) and Dart isolates share no mutable '
                'memory; each gets port-sendable values; the store is one '
                'connection'),
    'V15.4.2': ('FINDING', 'concurrency_probe_before_fixes.tsv, bursts of 10, '
                '5 repeats: 10 conditional creates made 10 Patients; one '
                'refresh token was used 10 times; two admins demoting each '
                'other left none; a taken username was 500. Fixed #84 #85 '
                '#86 #87 #88; concurrency_probe.tsv after: every case 5/5'),
    'V15.4.3': ('PASS', 'code read: fhirant takes no lock of its own (no '
                'mutex, semaphore or lock in lib); the only locks are '
                "SQLite's, held inside drift transactions on one connection; "
                'no retry loop (the while (true) loops page or parse)'),
    'V15.4.4': ('FINDING', 'CLI: the store runs on the server isolate, so a '
                '2,000-entry transaction Bundle blocked every other request '
                'for its whole run, 1.3-2.6 s; the app (createInBackground) '
                'waited at most 36-55 ms (starvation_probe.tsv; load 20 on '
                '16 cores, noisy). Not fixed: re-measure on a quiet machine '
                'first'),
    'V4.2.5': ('FINDING', 'outbound_crlf_probe: CR/LF in a header name or '
               'value refused by dart:io, endpoint CRLF percent-encoded; a '
               '64 KiB channel.header went out whole. Fixed #81: rest-hook '
               'lines bounded at 8190 bytes (Apache/nginx defaults), CR/LF '
               'refused at activation'),
    'V4.2.1': ('FINDING', 'smuggling_probe: dart:io 3.13 frames CL+TE by TE '
               'and keeps the connection (RFC 9112 6.1 MUST close); 9 '
               'malformed framings closed with no 400 (6.3, 5.1 MUST 400). '
               'Not fixable in fhirant (handler sees neither header); SDK '
               'issue drafted, DART-SDK-ISSUE-http-framing.md'),
    'V4.2.2': ('PASS', 'the two hand-set Content-Lengths match the bytes '
               'sent: export_scale_test, backup_file_e2e_test'),
    'V4.2.3': ('N/A', 'no HTTP/2 or HTTP/3: h2c preface gets 0 bytes and a '
               'close (smuggling_probe); no ALPN configured'),
    'V4.2.4': ('N/A', 'no HTTP/2 or HTTP/3 (see V4.2.3)'),
}


def main():
    d = json.load(open(sys.argv[1]))
    rows = []
    for ch in d['Requirements']:
        for sec in ch['Items']:
            if sec['Shortcode'] not in SECTIONS:
                sys.exit('no verdict for section ' + sec['Shortcode'])
            for r in sec['Items']:
                v, why = OVERRIDES.get(r['Shortcode'],
                                       SECTIONS[sec['Shortcode']])
                rows.append((r['Shortcode'], 'L%s' % r.get('L'), v, why,
                             r['Description'][:160]))
    out = os.path.join(HERE, 'asvs_walk.tsv')
    with open(out, 'w') as f:
        f.write('id\tlevel\tverdict\tevidence\trequirement\n')
        for row in rows:
            f.write('\t'.join(x.replace('\t', ' ') for x in row) + '\n')
    counts = {}
    for row in rows:
        counts[row[2]] = counts.get(row[2], 0) + 1
    print(len(rows), counts, '->', out, flush=True)


if __name__ == '__main__':
    main()
