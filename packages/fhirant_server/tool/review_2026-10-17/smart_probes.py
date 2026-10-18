#!/usr/bin/env python3
"""SMART App Launch 2.2.0 (app-launch.html, read 2026-10-17) probes for the
fifth fhirant review: PKCE, aud, redirect_uri, state, the code (short-lived,
single use), the token response and its headers, refresh (same client,
no widening), CORS on discovery and token endpoints.

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/smart_probes.py <server> <workdir>
"""
import base64
import hashlib
import json
import os
import shutil
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'smart_probes.tsv')
BASE = 'http://127.0.0.1:%d' % g.PORT
N = [0]


def log(case, rule, expected, observed, verdict):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in (case, rule, expected, observed, verdict))
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def ip():
    # The credential limiter allows 10 per minute per address.
    N[0] += 1
    return '127.0.8.%d' % (N[0] % 250 + 1)


def pkce():
    v = base64.urlsafe_b64encode(os.urandom(40)).rstrip(b'=').decode()
    c = base64.urlsafe_b64encode(hashlib.sha256(v.encode()).digest()) \
        .rstrip(b'=').decode()
    return v, c


def authorize(client='app1', redirect='https://app.example/cb',
              scope='patient/*.rs openid fhirUser launch/patient',
              state='st-123', aud=BASE, method='S256', challenge=None,
              user='pat', extra=None, http_method='POST'):
    v, c = pkce()
    p = {'response_type': 'code', 'client_id': client,
         'redirect_uri': redirect, 'scope': scope, 'state': state,
         'aud': aud, 'code_challenge': challenge or c,
         'code_challenge_method': method, 'username': user,
         'password': g.PW}
    if extra:
        p.update(extra)
    p = {k: v2 for k, v2 in p.items() if v2 is not None}
    if http_method == 'POST':
        s, h, b = g.req('POST', '/auth/authorize', urllib.parse.urlencode(p),
                        ip=ip(), headers={'Accept': '*/*'})
    else:
        s, h, b = g.req('GET', '/auth/authorize?' + urllib.parse.urlencode(p),
                        ip=ip(), headers={'Accept': '*/*'})
    loc = h.get('Location') or h.get('location') or ''
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(loc).query)
    return s, h, b, loc, q, v


def token(form):
    s, h, b = g.req('POST', '/auth/token', urllib.parse.urlencode(form),
                    ip=ip(), headers={'Accept': 'application/json'})
    try:
        j = json.loads(b)
    except ValueError:
        j = {}
    return s, h, j, b


def exchange(code, verifier, client='app1',
             redirect='https://app.example/cb'):
    return token({'grant_type': 'authorization_code', 'code': code,
                  'redirect_uri': redirect, 'code_verifier': verifier,
                  'client_id': client})


def hget(h, k):
    for a, b in h.items():
        if a.lower() == k.lower():
            return b
    return None


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\trule\texpected\tobserved\tverdict\n')
    d = os.path.join(work, 'smart')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        run()
    finally:
        g.stop(p)


def run():
    s, h, b = g.req('GET', '/.well-known/smart-configuration',
                    headers={'Accept': 'application/json'})
    cfg = json.loads(b)
    log('discovery', 'conformance.html', 'read', {k: cfg.get(k) for k in (
        'authorization_endpoint', 'token_endpoint',
        'code_challenge_methods_supported', 'capabilities',
        'grant_types_supported', 'scopes_supported')}, 'NOTE')
    log('discovery lists S256 only', 'SMART servers SHALL support the S256 '
        'code_challenge_method and SHALL NOT support the plain method',
        "['S256']", cfg.get('code_challenge_methods_supported'),
        'PASS' if cfg.get('code_challenge_methods_supported') == ['S256']
        else 'FAIL')

    # The happy path, POST and GET.
    s, h, b, loc, q, v = authorize()
    log('authorize POST', 'Authorization Servers SHALL support the use of '
        'the HTTP GET and POST methods', '302 with code + state', (s, loc[:120]),
        'PASS' if s == 302 and q.get('code') else 'FAIL')
    log('state echoed', 'state: The exact value received from the client',
        'st-123', q.get('state'), 'PASS' if q.get('state') == ['st-123']
        else 'FAIL')
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, v)
    log('token exchange', 'SHALL return a JSON object that includes an '
        'access token', '200 access_token, token_type Bearer, scope, '
        'expires_in', (s, sorted(j.keys()), j.get('token_type'),
                       j.get('scope'), j.get('expires_in')),
        'PASS' if s == 200 and j.get('access_token') and
        str(j.get('token_type')).lower() == 'bearer' and 'scope' in j
        else 'FAIL')
    log('token no-store / no-cache', 'SHALL include the HTTP "Cache-Control" '
        'response header field with a value of "no-store," as well as the '
        '"Pragma" response header field with a value of "no-cache."',
        'no-store / no-cache', (hget(h, 'Cache-Control'), hget(h, 'Pragma')),
        'PASS' if hget(h, 'Cache-Control') and 'no-store' in
        hget(h, 'Cache-Control') and hget(h, 'Pragma') == 'no-cache'
        else 'FAIL')
    log('access token lifetime', 'Access tokens SHOULD have a valid lifetime '
        'no greater than one hour', '<= 3600', j.get('expires_in'),
        'PASS' if j.get('expires_in') and int(j['expires_in']) <= 3600
        else 'FAIL')
    log('patient context in token response', 'a parameter like "patient": '
        '"123" MAY BE included', 'pat1', j.get('patient'), 'NOTE')
    at, rt = j.get('access_token'), j.get('refresh_token')
    if at:
        s2, _, b2 = g.req('GET', '/Patient/pat1', token=at, ip=ip())
        log('token works on the FHIR API', 'Access FHIR API', 200, s2,
            'PASS' if s2 == 200 else 'FAIL')
        claims = g.claims_of(at)
        log('token aud claim', 'The resource server also validates that the '
            'aud parameter associated with the authorization matches the '
            "resource server's own FHIR endpoint", 'aud present',
            claims.get('aud'), 'NOTE')
    s, h, j2, b = exchange(code, v)
    log('code reuse', 'authorization code ... single use (RFC 6749 4.1.2: '
        'MUST NOT be used more than once)', '400 invalid_grant', (s, b[:120]),
        'PASS' if s == 400 else 'FAIL')
    if at:
        s3, _, _ = g.req('GET', '/Patient/pat1', token=at, ip=ip())
        log('tokens from a reused code revoked', 'RFC 6749 4.1.2: SHOULD '
            'revoke (when possible) all tokens previously issued based on '
            'that authorization code', '401', s3,
            'PASS' if s3 == 401 else 'FAIL')
    s, h, b, loc, q, v = authorize(http_method='GET')
    log('authorize GET with credentials in query', 'GET supported (OIDC '
        '3.1.2.1); credentials in a URL are logged', 'read', (s, loc[:100]),
        'NOTE')

    # PKCE
    s, h, b, loc, q, v = authorize()
    code = (q.get('code') or [''])[0]
    s, h, j, b = token({'grant_type': 'authorization_code', 'code': code,
                        'redirect_uri': 'https://app.example/cb',
                        'client_id': 'app1'})
    log('missing code_verifier', 'the EHR SHALL ensure that the '
        'code_verifier is present and valid', '400', (s, b[:120]),
        'PASS' if s == 400 else 'FAIL')
    s, h, b, loc, q, v = authorize()
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, 'x' * 50)
    log('wrong code_verifier', 'present and valid', '400', (s, b[:120]),
        'PASS' if s == 400 else 'FAIL')
    s, h, b, loc, q, v = authorize(method='plain', challenge='p' * 50)
    log('plain method', 'SHALL NOT support the plain method', 'refused',
        (s, loc[:120] or b[:120]), 'PASS' if not q.get('code') else 'FAIL')
    s, h, b, loc, q, v = authorize(method=None, challenge=None,
                                   extra={'code_challenge': None})
    log('no PKCE at all', 'code_challenge required', 'refused',
        (s, loc[:120] or b[:120]), 'PASS' if not q.get('code') else 'FAIL')

    # aud
    for a in ['https://evil.example/fhir', '', BASE + '/', BASE.upper()]:
        s, h, b, loc, q, v = authorize(aud=a or None)
        log('aud=%r' % a, 'servers SHALL support the aud parameter (prevents '
            'leaking a genuine bearer token to a counterfeit resource '
            'server)', 'refused unless it names this server',
            (s, loc[:120] or b[:120]),
            'PASS' if (a in (BASE + '/',) or bool(q.get('code')) ==
                       (a == BASE)) else 'FAIL')

    # redirect_uri pinning and exchange
    s, h, b, loc, q, v = authorize(client='app2',
                                   redirect='https://two.example/cb')
    s, h, b, loc, q, v = authorize(client='app2',
                                   redirect='https://evil.example/cb')
    log('redirect_uri other than registered', 'redirect_uri Must match one '
        "of the client's pre-registered redirect URIs", 'no redirect to evil',
        (s, loc[:120]), 'PASS' if 'evil' not in loc else 'FAIL')
    s, h, b, loc, q, v = authorize(client='app3',
                                   redirect='https://three.example/cb')
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, v, client='app3',
                          redirect='https://three.example/other')
    log('exchange with a different redirect_uri', 'redirect_uri: The same '
        'redirect_uri used in the initial authorization request', '400',
        (s, b[:120]), 'PASS' if s == 400 else 'FAIL')
    s, h, b, loc, q, v = authorize(client='app4',
                                   redirect='https://four.example/cb')
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, v, client='other-client',
                          redirect='https://four.example/cb')
    log('exchange by another client_id', 'code bound to the client', '400',
        (s, b[:120]), 'PASS' if s == 400 else 'FAIL')
    for r in ['javascript:alert(1)', 'http://app.example/cb#frag',
              'not a url']:
        s, h, b, loc, q, v = authorize(client='c-' + str(abs(hash(r)) % 999),
                                       redirect=r)
        log('redirect_uri %r' % r, 'RFC 6749 3.1.2: absolute URI, no '
            'fragment', 'refused', (s, loc[:100] or b[:100]),
            'PASS' if not q.get('code') else 'FAIL')

    # scope handling
    s, h, b, loc, q, v = authorize(user='pat', scope='system/*.* user/*.*')
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, v)
    log('scope wider than the account', 'Scope of access authorized ... can '
        'be different from the scopes requested', 'no system/ or user/ '
        'for a patient account', (s, j.get('scope')),
        'PASS' if s != 200 or ('system/' not in (j.get('scope') or '') and
                               'user/' not in (j.get('scope') or ''))
        else 'FAIL')

    # refresh
    s, h, b, loc, q, v = authorize(scope='patient/*.rs offline_access')
    code = (q.get('code') or [''])[0]
    s, h, j, b = exchange(code, v)
    rt = j.get('refresh_token')
    log('refresh token issued for offline_access', 'If granted, the EHR '
        'supplies a refresh_token', 'present', bool(rt), 'NOTE')
    if rt:
        s, h, j2, b = token({'grant_type': 'refresh_token',
                             'refresh_token': rt})
        log('refresh response', 'access_token, token_type, expires_in '
            '(required), scope (required)', 'all four',
            (s, sorted(j2.keys())), 'PASS' if s == 200 and all(
                k in j2 for k in ('access_token', 'token_type', 'expires_in',
                                  'scope')) else 'FAIL')
        log('refresh no-store', 'Cache-Control no-store, Pragma no-cache',
            'both', (hget(h, 'Cache-Control'), hget(h, 'Pragma')),
            'PASS' if hget(h, 'Pragma') == 'no-cache' else 'FAIL')
        s, h, j3, b = token({'grant_type': 'refresh_token',
                             'refresh_token': j2.get('refresh_token') or rt,
                             'scope': 'patient/*.* user/*.*'})
        log('refresh widening scope', 'this value must be a strict sub-set of '
            'the scopes granted in the original launch', 'refused or not '
            'widened', (s, j3.get('scope'), b[:100]),
            'PASS' if s != 200 or j3.get('scope') in ('patient/*.rs',)
            or 'user/' not in (j3.get('scope') or '') else 'FAIL')
        s, h, j4, b = token({'grant_type': 'refresh_token',
                             'refresh_token': rt})
        log('old refresh token after rotation', 'the app should discard any '
            'previous refresh_token', 'refused if rotated', (s, b[:100]),
            'NOTE')

    # CORS
    for path, method in [('/.well-known/smart-configuration', 'GET'),
                         ('/metadata', 'GET'), ('/auth/token', 'OPTIONS'),
                         ('/Patient', 'OPTIONS')]:
        hdr = {'Origin': 'https://app.example'}
        if method == 'OPTIONS':
            hdr['Access-Control-Request-Method'] = 'POST'
        s, h, b = g.req(method, path, headers=hdr, ip=ip())
        log('CORS %s %s' % (method, path), 'Servers that support purely '
            'browser-based apps SHALL enable CORS: discovery from any origin; '
            'token and FHIR API from registered origins', 'read',
            (s, hget(h, 'Access-Control-Allow-Origin')), 'NOTE')


if __name__ == '__main__':
    main()
