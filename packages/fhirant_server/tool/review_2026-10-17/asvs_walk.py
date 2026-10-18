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
    'V1.2.4': ('PASS', 'asvs_probes: values, names, _sort, chains, _has'),
    'V1.3.6': ('PASS', 'no outbound request to 7 client-named URLs'),
    'V2.4.1': ('PASS', 'limiter counts the socket address'),
    'V6.2.4': ('FINDING', 'P1: 20 common passwords, not 3000'),
    'V6.2.12': ('NOTPROBED', 'no breached-password check'),
    'V7.3.1': ('FINDING', 'no inactivity timeout'),
    'V10.4.8': ('FINDING', 'R1: each rotation grants a fresh 7 days'),
    'V9.2.1': ('FINDING', 'a signed token without exp never expires'),
    'V9.2.3': ('NOTPROBED', 'no aud claim; single service'),
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
