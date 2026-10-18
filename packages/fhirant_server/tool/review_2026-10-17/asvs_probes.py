#!/usr/bin/env python3
"""OWASP ASVS 5.0.0 probes for the fifth fhirant review (2026-10-17): the
requirements the walk (asvs_walk.tsv) marked "probe". One row per case to
asvs_probes.tsv: ASVS id, case, observed, verdict.

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/asvs_probes.py <server> <workdir>
"""
import base64
import http.client
import http.server
import json
import os
import shutil
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402
import subscription_probes as sp  # noqa: E402

OUT = os.path.join(g.HERE, 'asvs_probes.tsv')
N = [0]


def log(aid, case, observed, verdict):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in (aid, case, observed, verdict))
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def ip():
    N[0] += 1
    return '127.0.10.%d' % (N[0] % 250 + 1)


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('asvs\tcase\tobserved\tverdict\n')
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', sp.HOOK_PORT),
                                          sp.Hook)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    d = os.path.join(work, 'asvs')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        run(d)
    finally:
        g.stop(p)
        srv.shutdown()


def run(d):
    adm, _ = g.login('adm2', g.PW, ip())
    pat, _ = g.login('pat', g.PW, ip())

    def r(m, path, b=None, tok=None, h=None):
        return g.req(m, path, b, adm if tok is None else tok, h, ip=ip())

    # V1.2.4 SQL injection through search values, names, _sort, chains.
    inj = ["x' OR '1'='1", "x'; DROP TABLE resources;--", 'x" OR "1"="1',
           "x%' OR 1=1--", "\\' OR 1=1--", "x') OR ('1'='1"]
    for q in ['name', 'family', 'identifier', '_id', 'general-practitioner',
              'name:contains', 'address-city:exact']:
        worst = []
        for v in inj:
            s, _, b = r('GET', '/Patient?%s=%s' % (q, urllib.parse.quote(v)))
            tot = json.loads(b).get('total') if s == 200 else None
            worst.append((s, tot))
        bad = [w for w in worst if w[0] >= 500 or (w[1] or 0) > 0]
        log('V1.2.4', 'injection in Patient?%s=' % q, worst,
            'FAIL' if bad else 'PASS')
    for path in ["/Patient?_sort=family%27%20DESC--",
                 "/Observation?subject:Patient.family=x%27%20OR%201%3D1--",
                 "/Patient?_has:Observation:subject:code=x%27%20OR%20%271%27"
                 "%3D%271", "/Patient?name%27--=x",
                 "/Observation?value-quantity=1%27%20OR%201%3D1",
                 "/Observation?date=2020%27%20OR%201%3D1"]:
        s, _, b = r('GET', path)
        tot = json.loads(b).get('total') if s == 200 else b[:80]
        # 2 = every Patient: an ignored parameter, not an injection.
        log('V1.2.4', 'injection %s' % path, (s, tot),
            'FAIL' if s >= 500 or (s == 200 and tot not in (0, 2))
            else 'PASS')
    s, _, b = r('GET', '/Patient?_count=1')
    log('V1.2.4', 'store intact after injection probes', (s, json.loads(b)
                                                          .get('total')),
        'PASS' if s == 200 else 'FAIL')

    # V1.3.6 / V13.2.4 SSRF: does any operation fetch a URL the client names?
    hook = 'http://127.0.0.1:%d' % sp.HOOK_PORT
    sp.RECEIVED.clear()
    probes = [
        ('POST', '/Patient/$validate?profile=%s/ssrf-validate' % hook,
         {'resourceType': 'Patient'}),
        ('POST', '/$validate', {'resourceType': 'Patient', 'meta': {
            'profile': [hook + '/ssrf-meta-profile']}}),
        ('GET', '/ValueSet/$expand?url=%s/ssrf-expand' % urllib.parse.quote(
            hook), None),
        ('GET', '/CodeSystem/$lookup?system=%s/ssrf-lookup&code=x'
         % urllib.parse.quote(hook), None),
        ('POST', '/$transform', {'resourceType': 'Parameters', 'parameter': [
            {'name': 'source', 'valueUri': hook + '/ssrf-map'},
            {'name': 'content', 'resource': {'resourceType': 'Patient'}}]}),
        ('POST', '/Library/$evaluate', {'resourceType': 'Parameters',
                                        'parameter': [{'name': 'url',
                                                       'valueString': hook +
                                                       '/ssrf-lib'}]}),
        ('POST', '/$cql', {'cql': "library X version '1'\nusing FHIR version "
                           "'4.0.1'\ninclude Y version '1' called Y\n"
                           "define N: 1", 'subject': 'Patient/pat1'}),
    ]
    for m, path, b in probes:
        s, _, body = r(m, path, b)
        log('V1.3.6', 'SSRF candidate %s %s' % (m, path.split('?')[0]),
            (s, body[:100]), 'NOTE')
    time.sleep(2)
    hits = [x['path'] for x in sp.RECEIVED]
    log('V1.3.6', 'outbound requests the server made to the client-named '
        'URL', hits, 'FAIL' if hits else 'PASS')

    # V1.2.1 / V3.2.1 reflected markup on the HTML auth pages.
    x = '<script>alert(1)</script>'
    for name, q in [('client_id', {'client_id': x}),
                    ('redirect_uri', {'redirect_uri': x}),
                    ('scope', {'scope': x}), ('state', {'state': x}),
                    ('response_type', {'response_type': x})]:
        params = {'response_type': 'code', 'client_id': 'xss',
                  'redirect_uri': 'https://xss.example/cb', 'scope': 'x',
                  'state': 's', 'aud': 'http://127.0.0.1:%d' % g.PORT,
                  'code_challenge': 'A' * 43, 'code_challenge_method': 'S256'}
        params.update(q)
        s, h, b = g.req('GET', '/auth/authorize?' +
                        urllib.parse.urlencode(params), ip=ip(),
                        headers={'Accept': 'text/html,application/xhtml+xml,'
                                 'application/xml;q=0.9,*/*;q=0.8'})
        log('V1.2.1', 'authorize page reflects %s' % name,
            (s, (h.get('Content-Type') or h.get('content-type')),
             x in b, h.get('Content-Security-Policy') or
             h.get('content-security-policy')),
            'FAIL' if x in b else 'PASS')

    # V5.3.2 path traversal on the export file route.
    seed = json.load(open(g.SEED_OUT))
    job = seed['job']
    for f in ['..%2F..%2Fdb%2Ffhirant.db', '..%2Fdb%2Ffhirant.db',
              '%2E%2E%2F%2E%2E%2Fserver.log', '....//....//server.log',
              '..%5C..%5Cserver.log', '%252E%252E%252Fserver.log']:
        s, _, b = r('GET', '/$export-file/%s/%s' % (job, f),
                    h={'Accept': '*/*'})
        log('V5.3.2', 'export file name %s' % f, (s, len(b), b[:60]),
            'FAIL' if s == 200 else 'PASS')
    for j in ['..%2F..%2Fdb', '..', '%2E%2E']:
        s, _, b = r('GET', '/$export-file/%s/fhirant.db' % j,
                    h={'Accept': '*/*'})
        log('V5.3.2', 'export job id %s' % j, (s, len(b)),
            'FAIL' if s == 200 else 'PASS')

    # V13.4.4 / V4.1.4 methods
    for m in ['TRACE', 'CONNECT', 'PROPFIND', 'FOO']:
        c = http.client.HTTPConnection('127.0.0.1', g.PORT, timeout=10)
        try:
            c.request(m, '/Patient', headers={'Authorization': 'Bearer ' +
                                                adm})
            resp = c.getresponse()
            body = resp.read()
            log('V13.4.4', 'method %s' % m, (resp.status, body[:80]),
                'FAIL' if resp.status < 300 else 'PASS')
        except Exception as e:
            log('V13.4.4', 'method %s' % m, repr(e), 'PASS')
        finally:
            c.close()

    # V14.3.2 / V14.2.2 anti-caching on PHI
    for path in ['/Patient/pat1', '/Observation?subject=Patient/pat1',
                 '/Patient/pat1/$everything']:
        s, h, b = r('GET', path)
        cc = h.get('Cache-Control') or h.get('cache-control')
        log('V14.3.2', 'Cache-Control on %s' % path, (s, cc),
            'PASS' if cc and 'no-store' in cc else 'FAIL')

    # V15.3.4 / V4.1.3 X-Forwarded-For cannot dodge the credential limiter.
    codes = []
    for i in range(14):
        s, _, _ = g.req('POST', '/auth/login', {'username': 'nobody',
                                                'password': 'x' * 12},
                        ip='127.0.11.1',
                        headers={'X-Forwarded-For': '10.9.%d.%d' % (i, i),
                                 'X-Real-IP': '10.8.%d.1' % i})
        codes.append(s)
    log('V15.3.4', '14 logins, one socket address, 14 forwarded addresses',
        codes, 'PASS' if 429 in codes else 'FAIL')

    # V9.1.2 / V9.1.3 / V9.2.1 token checks
    good, _ = g.login('clin', g.PW, ip())
    claims = g.claims_of(good)

    def signed(header, cl, alg='sha256'):
        import hashlib
        import hmac
        h = g.b64(json.dumps(header).encode())
        c = g.b64(json.dumps(cl).encode())
        dig = getattr(hashlib, alg)
        sig = hmac.new(g.SECRET.encode(), ('%s.%s' % (h, c)).encode(),
                       dig).digest()
        return '%s.%s.%s' % (h, c, g.b64(sig))
    now = int(time.time())
    cases = [
        ('HS256 control', signed({'alg': 'HS256', 'typ': 'JWT'}, claims),
         200),
        ('HS384 with the real secret', signed({'alg': 'HS384', 'typ': 'JWT'},
                                              claims, 'sha384'), 'either'),
        ('HS512 with the real secret', signed({'alg': 'HS512', 'typ': 'JWT'},
                                              claims, 'sha512'), 'either'),
        ('header jwk (attacker key)', signed({'alg': 'HS256', 'typ': 'JWT',
                                              'jwk': {'kty': 'oct', 'k':
                                                      'YQ'}}, claims), 'either'),
        ('nbf in the future', signed({'alg': 'HS256', 'typ': 'JWT'},
                                     dict(claims, nbf=now + 3600)), 401),
        ('no exp', signed({'alg': 'HS256', 'typ': 'JWT'},
                          {k: v for k, v in claims.items() if k != 'exp'}),
         401),
        ('exp as string', signed({'alg': 'HS256', 'typ': 'JWT'},
                                 dict(claims, exp=str(now + 3600))), 401),
        ('iat far future', signed({'alg': 'HS256', 'typ': 'JWT'},
                                  dict(claims, iat=now + 10 ** 6)), 'either'),
        ('RS256 header, HMAC body', signed({'alg': 'RS256', 'typ': 'JWT'},
                                           claims), 401),
    ]
    for name, tok, want in cases:
        s, _, b = g.req('GET', '/Patient/pat1', token=tok, ip=ip())
        ok = (s == want) if want != 'either' else True
        log('V9.1/V9.2', 'token: %s' % name, s, 'PASS' if ok and
            want != 'either' else ('NOTE' if want == 'either' else 'FAIL'))
    s, _, _ = g.req('GET', '/Patient/pat1', token='x' * 20000, ip=ip())
    log('V9.1', 'token of 20,000 characters', s, 'PASS' if s in (400, 401,
                                                                431)
        else 'FAIL')

    # V6.2 password policy (register as admin)
    def reg(u, pw):
        s, _, b = g.req('POST', '/auth/register', {'username': u,
                                                   'password': pw},
                        adm, ip=ip())
        return s, b[:100]
    for u, pw in [('p8', 'abcdefgh'), ('p11', 'abcdefghijk'),
                  ('p12', 'k7#Lm2$qZx9!'), ('p15', 'correcthorsebat'),
                  ('p64', 'q' * 63 + 'Z'), ('p128', 'w' * 127 + 'Y'),
                  ('p129', 'e' * 128 + 'R'), ('pall', 'aaaaaaaaaaaaaaaa'),
                  ('pkb', '1qaz2wsx3edc4rfv'), ('pq', 'qwertyuiopasdfgh'),
                  ('puni', 'pässwörd-über-long')]:
        s, b = reg('pw-' + u, pw)
        log('V6.2', 'register password %r (%d chars)' % (
            pw if len(pw) < 20 else pw[:6] + '...', len(pw)), (s, b), 'NOTE')
    # V6.2.8 no truncation / transformation
    longpw = 'Zq' + 'x' * 100 + 'END1'
    reg('pw-trunc', longpw)
    a = g.req('POST', '/auth/login', {'username': 'pw-trunc',
                                      'password': longpw[:72]}, ip=ip())[0]
    b2 = g.req('POST', '/auth/login', {'username': 'pw-trunc',
                                       'password': longpw.upper()},
               ip=ip())[0]
    c2 = g.req('POST', '/auth/login', {'username': 'pw-trunc',
                                       'password': longpw}, ip=ip())[0]
    log('V6.2.8', 'login with first 72 chars / upper-cased / exact',
        (a, b2, c2), 'PASS' if (a, b2, c2) == (401, 401, 200) else 'FAIL')

    # V6.3.8 enumeration by timing (L3)
    def t(user):
        ts = []
        for _ in range(6):
            t0 = time.time()
            g.req('POST', '/auth/login', {'username': user,
                                          'password': 'wrong-password-123'},
                  ip=ip())
            ts.append(time.time() - t0)
        ts.sort()
        return round(ts[len(ts) // 2] * 1000, 1)
    log('V6.3.8', 'median ms: unknown user / known user wrong password',
        (t('no-such-user-zz'), t('deact')), 'NOTE')

    # V10.4.5 refresh reuse: replaying a used refresh token must revoke the
    # family.
    _, rt = g.login('rdonly', g.PW, ip())
    time.sleep(1.2)
    s1, _, b1 = g.req('POST', '/auth/token', 'grant_type=refresh_token&'
                      'refresh_token=' + rt, ip=ip())
    rt2 = json.loads(b1).get('refresh_token')
    time.sleep(1.2)
    s2, _, b2 = g.req('POST', '/auth/token', 'grant_type=refresh_token&'
                      'refresh_token=' + rt, ip=ip())
    s3, _, b3 = g.req('POST', '/auth/token', 'grant_type=refresh_token&'
                      'refresh_token=' + (rt2 or ''), ip=ip())
    log('V10.4.5', 'rotate, replay old, then use the new one',
        (s1, s2, s3), 'PASS' if s2 in (400, 401) and s3 in (400, 401)
        else 'FAIL')
    # V10.4.8 absolute refresh lifetime
    _, rt = g.login('pat', g.PW, ip())
    e0 = g.claims_of(rt).get('exp')
    time.sleep(2.1)
    s, _, b = g.req('POST', '/auth/token', 'grant_type=refresh_token&'
                    'refresh_token=' + rt, ip=ip())
    rtn = json.loads(b).get('refresh_token')
    e1 = g.claims_of(rtn).get('exp') if rtn else None
    log('V10.4.8', 'refresh exp before/after rotation (absolute cap?)',
        (e0, e1, None if e1 is None else e1 - e0),
        'PASS' if e1 is not None and e1 <= e0 else 'FAIL')

    # V15.3.3 mass assignment: server-owned extensions on a Subscription.
    comp = ('http://fhirant.fhir-fli.dev/StructureDefinition/'
            'subscription-compartment')
    fail = ('http://fhirant.fhir-fli.dev/StructureDefinition/'
            'subscription-consecutive-failures')
    s, _, b = r('POST', '/Subscription', {
        'resourceType': 'Subscription', 'status': 'requested',
        'reason': 'x', 'criteria': 'Observation?code=8867-4',
        'channel': {'type': 'websocket'},
        'extension': [{'url': comp, 'valueReference': {'reference':
                                                       'Patient/pat2'}},
                      {'url': fail, 'valueInteger': 4}]}, tok=pat)
    j = json.loads(b) if s < 300 else {}
    exts = [(e['url'].rsplit('/', 1)[-1], e.get('valueReference', {})
             .get('reference') or e.get('valueInteger'))
            for e in j.get('extension', [])]
    log('V15.3.3', 'patient-scoped client sets the compartment/failure '
        'extensions itself', (s, exts),
        'FAIL' if ('subscription-compartment', 'Patient/pat2') in exts
        else 'PASS')
    if j.get('id'):
        w = sp.WS(pat)
        w.send('bind ' + j['id'])
        w.recv()
        r('POST', '/Observation', {'resourceType': 'Observation',
                                   'status': 'final', 'code': {'coding': [{
                                       'system': 'http://loinc.org',
                                       'code': '8867-4'}]},
                                   'subject': {'reference': 'Patient/pat2'}})
        msg = w.recv(6)
        log('V15.3.3', 'that subscription pings on pat2 data', msg,
            'FAIL' if msg else 'PASS')

    # V5.2.1 body size and structure
    big = '{"resourceType":"Patient","name":[{"family":"' + 'a' * (17 << 20) \
        + '"}]}'
    s, _, b = r('POST', '/Patient', big)
    log('V5.2.1', '17 MiB body', s, 'PASS' if s == 413 else 'FAIL')
    deep = '{"resourceType":"Patient","extension":' + '[' * 100000 + \
        ']' * 100000 + '}'
    t0 = time.time()
    try:
        s, _, b = r('POST', '/Patient', deep)
    except Exception as e:
        s, b = 'EXC', repr(e)
    log('V5.2.1', 'JSON nested 100,000 deep (%.0f KB)' % (len(deep) / 1024),
        (s, round(time.time() - t0, 1), b[:100]),
        'PASS' if s in (400, 413, 422) else 'FAIL')
    s2, _, _ = r('GET', '/metadata')
    log('V5.2.1', 'server alive after the deep body', s2,
        'PASS' if s2 == 200 else 'FAIL')
    t0 = time.time()
    s, _, b = r('GET', "/$fhirpath?expression=" + urllib.parse.quote(
        "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!'.matches('(a+)+$')") +
        '&resourceType=Patient&resourceId=pat1')
    log('V1.3.12', 'catastrophic regex in $fhirpath', (s, round(
        time.time() - t0, 1), b[:100]), 'PASS' if s != 200 or
        time.time() - t0 < 12 else 'FAIL')
    s2, _, _ = r('GET', '/metadata')
    log('V1.3.12', 'server alive after the regex', s2,
        'PASS' if s2 == 200 else 'FAIL')
    t0 = time.time()
    s, _, b = r('GET', '/Patient?name:contains=' + 'a' * 5000)
    log('V1.3.12', 'search value of 5,000 chars', (s, round(time.time() - t0,
                                                            2)), 'NOTE')

    # V16.4.1 log injection
    g.req('GET', '/Patient%0d%0a%7B%22level%22%3A%22SEVERE%22%7D', token=adm,
          ip=ip())
    g.req('POST', '/auth/login', {'username': 'evil\n{"level":"SEVERE",'
                                  '"message":"forged"}', 'password': 'x' * 12},
          ip=ip())
    time.sleep(0.5)
    lines = open(os.path.join(d, 'server.log')).read().splitlines()
    forged = [x for x in lines if '"message":"forged"' in x and
              not x.startswith('{"timestamp"')]
    bad = 0
    for x in lines:
        if x.startswith('{'):
            try:
                json.loads(x)
            except ValueError:
                bad += 1
    log('V16.4.1', 'forged log lines / unparsable JSON lines', (len(forged),
                                                                bad),
        'PASS' if not forged else 'FAIL')
    # V16.2.5 secrets in logs
    joined = '\n'.join(lines)
    log('V16.2.5', 'passwords / tokens in server.log',
        {'password': g.PW in joined, 'token': adm[:40] in joined},
        'FAIL' if g.PW in joined or adm[:40] in joined else 'PASS')
    # V14 files at rest
    for root, _, fs in os.walk(d):
        for f in fs:
            pth = os.path.join(root, f)
            mode = oct(os.stat(pth).st_mode & 0o777)
            if f.endswith(('.db', '.db-wal', '.db-shm', '.ndjson', 'token',
                           'secret', '.enc')) or 'export' in root:
                log('V14.1', 'file mode %s' % os.path.relpath(pth, d), mode,
                    'NOTE')


if __name__ == '__main__':
    main()
