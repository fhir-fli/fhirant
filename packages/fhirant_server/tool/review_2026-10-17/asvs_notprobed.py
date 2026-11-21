#!/usr/bin/env python3
"""Probes for the 31 ASVS 5.0.0 requirements the fifth review left
NOTPROBED (asvs_walk.tsv), 2026-11-21. One row per case to
asvs_notprobed.tsv: ASVS id, case, observed, verdict. A requirement that
is a property of the code or the deployment, not of an answer, is
settled in asvs_walk.py with the file it was read in; this script measures
what a running server does.

Three compiled CLI servers on this machine: X and Y share one JWT secret
(the multi-instance setup bin/server.dart describes), Z is started without
FHIRANT_JWT_SECRET so it writes its own secret file.

Run from packages/fhirant_server:
  python3 -I tool/review_2026-10-17/asvs_notprobed.py <server> <workdir>
"""
import base64
import hashlib
import http.client
import http.server
import json
import os
import shutil
import socket
import ssl
import stat
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'asvs_notprobed.tsv')
PX, PY, PZ = 18411, 18412, 18413
HOOK, TLS_HOOK, TLS_PEER = 18490, 18491, 18492
RECEIVED = []
N = [0]


def log(aid, case, observed, verdict):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:500]
                     for x in (aid, case, observed, verdict))
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def ip():
    N[0] += 1
    return '127.0.20.%d' % (N[0] % 250 + 1)


def on(port):
    g.PORT = port


def start(port, dbdir, cwd, secret=True):
    env = dict(os.environ)
    env.update({'FHIRANT_ENCRYPTION_KEY': g.KEY,
                'FHIRANT_ADMIN_USERNAME': g.ROOT[0],
                'FHIRANT_ADMIN_PASSWORD': g.ROOT[1]})
    if secret:
        env['FHIRANT_JWT_SECRET'] = g.SECRET
    else:
        env.pop('FHIRANT_JWT_SECRET', None)
    os.makedirs(cwd, exist_ok=True)
    logf = open(os.path.join(cwd, 'server.log'), 'w')
    p = subprocess.Popen(
        [g.BIN, '--port', str(port), '--db-path', dbdir, '--spec-path',
         g.SPEC], cwd=cwd, env=env, stdout=logf, stderr=subprocess.STDOUT)
    with open(os.path.join(cwd, 'pid'), 'w') as f:
        f.write(str(p.pid))
    on(port)
    for _ in range(120):
        try:
            if g.req('GET', '/health', ip=g.ROOT_IP, timeout=2)[0] == 200:
                return p
        except OSError:
            pass
        if p.poll() is not None:
            raise RuntimeError('server exited %s' % p.returncode)
        time.sleep(0.5)
    p.kill()
    raise RuntimeError('server on %d did not answer /health' % port)


def raw(method, path, data=b'', headers=None, token=None, port=None):
    h = dict(headers or {})
    if token:
        h['Authorization'] = 'Bearer ' + token
    c = http.client.HTTPConnection('127.0.0.1', port or g.PORT, timeout=120,
                                   source_address=(ip(), 0))
    try:
        c.request(method, path, body=data, headers=h)
        r = c.getresponse()
        return r.status, dict(r.getheaders()), r.read()
    finally:
        c.close()


def account(admin, username, password, **extra):
    body = dict({'username': username, 'role': 'clinician'}, **extra)
    cs, cb, s, uid = g.make_account(admin, body, password, ip())
    assert s == 200, (username, cs, cb, s)
    tok, _ = g.login(username, password, ip())
    return uid, tok


class Hook(http.server.BaseHTTPRequestHandler):
    def _any(self):
        n = int(self.headers.get('Content-Length') or 0)
        if n:
            self.rfile.read(n)
        RECEIVED.append((self.server.server_port, self.command, self.path))
        self.send_response(200)
        self.send_header('Content-Length', '0')
        self.end_headers()
    do_POST = do_PUT = do_GET = _any

    def log_message(self, *a):
        pass


def listener(port, cert=None):
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', port), Hook)
    if cert:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert[0], cert[1])
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def waited(pred, secs=10):
    end = time.time() + secs
    while time.time() < end:
        hit = [x for x in RECEIVED if pred(x)]
        if hit:
            return hit
        time.sleep(0.25)
    return []


def ids(body):
    return sorted(e['resource']['id'] for e in
                  json.loads(body).get('entry', []))


def authorize_query(client, redirect, scope='user/Patient.rs', port=PX):
    verifier = base64.urlsafe_b64encode(os.urandom(32)).rstrip(b'=')
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier).digest()).rstrip(b'=').decode()
    return {'response_type': 'code', 'client_id': client,
            'redirect_uri': redirect, 'scope': scope, 'state': 'st1',
            'code_challenge': challenge, 'code_challenge_method': 'S256',
            'aud': 'http://127.0.0.1:%d' % port}


def hibp_count(password):
    """Times [password] appears in Have I Been Pwned's Pwned Passwords, by
    the range API (only the first five hex digits of its SHA-1 are sent;
    these are well-known test strings, not anyone's password)."""
    h = hashlib.sha1(password.encode()).hexdigest().upper()
    req = urllib.request.Request(
        'https://api.pwnedpasswords.com/range/' + h[:5],
        headers={'User-Agent': 'asvs-probe'})
    body = urllib.request.urlopen(req, timeout=20).read().decode()
    for line in body.splitlines():
        suffix, count = line.split(':')
        if suffix == h[5:]:
            return int(count)
    return 0


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('asvs\tcase\tobserved\tverdict\n')
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    cert = (os.path.join(work, 'self.crt'), os.path.join(work, 'self.key'))
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048',
                    '-nodes', '-days', '1', '-subj', '/CN=127.0.0.1',
                    '-addext', 'subjectAltName=IP:127.0.0.1',
                    '-keyout', cert[1], '-out', cert[0]],
                   check=True, capture_output=True)
    hooks = [listener(HOOK), listener(TLS_HOOK, cert),
             listener(TLS_PEER, cert)]
    procs = []
    try:
        procs.append(start(PX, os.path.join(work, 'x', 'db'),
                           os.path.join(work, 'x')))
        backup = run_x(work)
        procs.append(start(PY, os.path.join(work, 'y', 'db'),
                           os.path.join(work, 'y')))
        run_y(backup)
        procs.append(start(PZ, os.path.join(work, 'z', 'db'),
                           os.path.join(work, 'z'), secret=False))
        run_z(work)
    finally:
        for p in procs:
            g.stop(p)
        for h in hooks:
            h.shutdown()


def run_x(work):
    on(PX)
    root, _ = g.login(g.ROOT[0], g.ROOT[1], g.ROOT_IP)

    def r(m, path, b=None, tok=None, h=None):
        return g.req(m, path, b, root if tok is None else tok, h, ip=ip())

    # V1.1.1: a search value is percent-decoded once. `family=%2541` is the
    # string "%41"; decoded twice it would be "A".
    for fam in ['%41', 'A']:
        s, _, b = r('POST', '/Patient', {'resourceType': 'Patient',
                                         'name': [{'family': fam}]})
        assert s == 201, b
    s1, _, b1 = r('GET', '/Patient?family:exact=%2541')
    s2, _, b2 = r('GET', '/Patient?family:exact=%41')
    fam1 = [e['resource']['name'][0]['family']
            for e in json.loads(b1).get('entry', [])]
    fam2 = [e['resource']['name'][0]['family']
            for e in json.loads(b2).get('entry', [])]
    log('V1.1.1', 'family:exact=%2541 finds "%41" only; =%41 finds "A" '
        'only', (s1, fam1, s2, fam2),
        'PASS' if fam1 == ['%41'] and fam2 == ['A'] else 'FAIL')
    # The same through a path segment: /Patient/%2541 names id "%41"
    # (not a legal id, 404/400), never the id "A".
    s, _, b = r('PUT', '/Patient/A', {'resourceType': 'Patient', 'id': 'A'})
    s3, _, b3 = r('GET', '/Patient/%2541')
    log('V1.1.1', 'GET /Patient/%2541 is not Patient/A', (s, s3, b3[:80]),
        'PASS' if s3 != 200 else 'FAIL')

    # V1.1.2: output encoding happens once, where the HTML is built.
    q = authorize_query('<b>"x&\'', 'http://127.0.0.1/cb')
    s, _, page = r('GET', '/auth/authorize?' + urllib.parse.urlencode(q),
                   tok='')
    once = '&lt;b&gt;&quot;x&amp;' in page
    twice = '&amp;lt;' in page or '&amp;quot;' in page
    raw_tag = '<b>"x' in page
    log('V1.1.2', 'client_id <b>"x&\' on the authorize page',
        (s, 'escaped once' if once else '', 'escaped twice' if twice
         else '', 'raw' if raw_tag else ''),
        'PASS' if once and not twice and not raw_tag else 'FAIL')

    # V3.7.1: what the authorize page asks the browser to run.
    tags = [t for t in ('<object', '<embed', '<applet', '<script',
                        'activex', '.swf') if t in page.lower()]
    log('V3.7.1', 'authorize page: plugin or script tags', tags or 'none',
        'PASS' if not tags else 'FAIL')

    # V3.7.2 / V3.7.3: the only redirect is to the client's redirect_uri.
    q = authorize_query('client-a', 'http://app.example/cb')
    form = dict(q, username=g.ROOT[0], password=g.ROOT[1])
    s, h, _ = raw('POST', '/auth/authorize',
                  urllib.parse.urlencode(form).encode(),
                  {'Content-Type': 'application/x-www-form-urlencoded'})
    loc = h.get('Location') or h.get('location') or ''
    log('V3.7.3', 'credentials posted: answer', (s, loc.split('?')[0]),
        'FINDING' if s in (302, 303) and loc.startswith('http://app.example')
        else 'NOTE')
    q = authorize_query('client-a', 'http://evil.example/cb')
    s, h, _ = r('GET', '/auth/authorize?' + urllib.parse.urlencode(q),
                tok='')
    log('V3.7.2', 'client-a, a second redirect_uri', (s, h.get('location')),
        'PASS' if s == 400 and not h.get('location') else 'FAIL')
    q = authorize_query('client-new', 'http://evil.example/cb')
    form = dict(q, username=g.ROOT[0], password=g.ROOT[1])
    s, h, _ = raw('POST', '/auth/authorize',
                  urllib.parse.urlencode(form).encode(),
                  {'Content-Type': 'application/x-www-form-urlencoded'})
    loc = h.get('Location') or h.get('location') or ''
    log('V3.7.2', 'a new client_id: any redirect host is pinned and used',
        (s, loc.split('?')[0]),
        'FINDING' if loc.startswith('http://evil.example') else 'PASS')

    # V10.7.1 / V10.7.2: what the user is shown before a code is issued.
    q = authorize_query('client-b', 'http://127.0.0.1/cb',
                        scope='patient/*.cruds offline_access')
    s, _, page = r('GET', '/auth/authorize?' + urllib.parse.urlencode(q),
                   tok='')
    shown = {'client named': 'client-b' in page,
             'scopes as raw strings': 'patient/*.cruds' in page,
             'lifetime': any(w in page.lower() for w in
                             ('hour', 'day', 'expire', 'lifetime')),
             'separate consent step': 'consent' in page.lower()}
    log('V10.7.2', 'authorize page content', shown,
        'FINDING' if not shown['lifetime'] else 'PASS')
    jq = dict(authorize_query('client-c', 'http://127.0.0.1/cb'),
              username=g.ROOT[0], password=g.ROOT[1])
    s, _, b = raw('POST', '/auth/authorize', json.dumps(jq).encode(),
                  {'Content-Type': 'application/json'})
    log('V10.7.1', 'JSON authorize: code issued with no page shown',
        (s, 'code' in json.loads(b or b'{}')),
        'FINDING' if s == 200 else 'PASS')

    # V10.7.3, V7.5.2: is there a route listing grants or sessions?
    for path in ['/auth/sessions', '/auth/grants', '/auth/consents',
                 '/admin/sessions']:
        s, _, b = r('GET', path)
        log('V7.5.2/V10.7.3', 'GET ' + path, (s, b[:120]),
            'FINDING' if s in (400, 404) else 'NOTE')

    # V6.2.12: passwords of policy length found in breach corpora.
    cand = ['password1234', 'qwertyuiop12', '123456789012', 'iloveyou1234',
            'football1234', 'princess1234', '1qaz2wsx3edc', 'zaq12wsxcde3',
            'Tr0ub4dor&3x', 'correcthorsebatterystaple', 'Summer2024!!',
            'Welcome2024!', 'Liverpool123', 'Manchester12']
    for i, pw in enumerate(cand):
        try:
            seen = hibp_count(pw)
        except OSError as e:
            seen = 'unknown (%s)' % e
        cs, cb, s, uid = g.make_account(
            root, {'username': 'bp%02d' % i, 'role': 'clinician'}, pw, ip())
        refused = cs == 400
        log('V6.2.12', 'claim with %r (HIBP count %s)' % (pw, seen),
            (cs, cb[:70] if refused else 'accepted'),
            'PASS' if refused or seen == 0 else 'FINDING')

    # V7.5.1: changing one's own password needs the current one.
    uid, tok = account(root, 'cara', 'Cara-Long-Passw0rd!')
    s1, _, b1 = r('POST', '/auth/password',
                  {'new_password': 'Cara-Other-Passw0rd!'}, tok)
    s2, _, b2 = r('POST', '/auth/password',
                  {'current_password': 'wrong-wrong-wrong',
                   'new_password': 'Cara-Other-Passw0rd!'}, tok)
    log('V7.5.1', 'password change without / with a wrong current password',
        (s1, s2), 'PASS' if s1 in (400, 401, 403) and s2 in (400, 401, 403)
        else 'FAIL')

    # V7.5.3: the most sensitive operations take the bearer token alone.
    s, _, b = raw('POST', '/$backup', json.dumps(
        {'resourceType': 'Parameters', 'parameter': [
            {'name': 'passphrase', 'valueString': 'probe-passphrase-1'}]})
        .encode(), {'Content-Type': 'application/fhir+json'}, token=root)
    log('V7.5.3', '$backup with the admin token only', (s, len(b)),
        'FINDING' if s == 200 else 'NOTE')
    s, _, _ = r('PUT', '/admin/users/%d/role' % uid, {'role': 'admin'})
    log('V7.5.3', 'make an account admin with the token only', s,
        'FINDING' if s == 200 else 'NOTE')
    backup = b

    # V9.2.3 / V10.3.1: the claims of a real token, and a token for another
    # service (same claims, another secret).
    claims = g.claims_of(root)
    log('V9.2.3', 'claims in an access token', sorted(claims),
        'FINDING' if 'aud' not in claims else 'PASS')
    other = g.sign({'alg': 'HS256', 'typ': 'JWT'}, claims,
                   'another-service-secret-' + 'c' * 40)
    s, _, _ = r('GET', '/Patient', tok=other)
    log('V10.3.1', 'same claims signed with another secret', s,
        'PASS' if s == 401 else 'FAIL')

    # V10.3.2: the token's scope decides.
    uid, narrow = account(root, 'nora', 'Nora-Long-Passw0rd!',
                          scopes=['user/Observation.rs'])
    sp_, _, _ = r('GET', '/Patient', tok=narrow)
    so, _, _ = r('GET', '/Observation', tok=narrow)
    log('V10.3.2', 'scope user/Observation.rs: Patient / Observation',
        (sp_, so), 'PASS' if sp_ == 403 and so == 200 else 'FAIL')

    # V10.3.5: a token works from any client address.
    s1, _, _ = g.req('GET', '/Observation', None, narrow, ip='127.0.30.1')
    s2, _, _ = g.req('GET', '/Observation', None, narrow, ip='127.0.31.7')
    log('V10.3.5', 'one token from two addresses', (s1, s2),
        'FINDING' if s2 == 200 else 'PASS')

    # V12.2.1: plain HTTP on every interface.
    lan = subprocess.run(['hostname', '-I'], capture_output=True,
                         text=True).stdout.split()
    lan = [a for a in lan if ':' not in a and not a.startswith('127.')]
    if lan:
        c = http.client.HTTPConnection(lan[0], PX, timeout=5)
        try:
            c.request('GET', '/health')
            st = c.getresponse().status
        except OSError as e:
            st = str(e)
        finally:
            c.close()
        log('V12.2.1', 'plain HTTP /health from this host\'s LAN address',
            st, 'FINDING' if st == 200 else 'NOTE')
    else:
        log('V12.2.1', 'plain HTTP from a LAN address', 'no LAN address',
            'NOTE')

    # V12.3.1 / V12.3.3: outbound rest-hook over plain HTTP.
    def sub(endpoint):
        return r('POST', '/Subscription', {
            'resourceType': 'Subscription', 'status': 'requested',
            'reason': 'probe', 'criteria': 'Observation?code=2823-3',
            'channel': {'type': 'rest-hook', 'endpoint': endpoint}})

    def obs():
        return r('POST', '/Observation', {
            'resourceType': 'Observation', 'status': 'final',
            'code': {'coding': [{'system': 'http://loinc.org',
                                 'code': '2823-3'}]}})

    s, _, b = sub('http://127.0.0.1:%d/plain' % HOOK)
    st = json.loads(b).get('status')
    RECEIVED.clear()
    obs()
    got = waited(lambda x: x[2] == '/plain')
    log('V12.3.1', 'rest-hook to http://: accepted, notified in clear',
        (s, st, len(got)), 'FINDING' if got else 'NOTE')
    # V12.3.2: a TLS endpoint whose certificate nothing vouches for.
    s, _, b = sub('https://127.0.0.1:%d/selfsigned' % TLS_HOOK)
    st = json.loads(b).get('status')
    sid = json.loads(b).get('id')
    RECEIVED.clear()
    obs()
    got = waited(lambda x: x[2] == '/selfsigned', 8)
    s2, _, b2 = r('GET', '/Subscription/%s' % sid)
    log('V12.3.2', 'rest-hook to a self-signed https endpoint',
        (s, st, 'delivered %d' % len(got),
         json.loads(b2).get('status'), json.loads(b2).get('error')),
        'PASS' if not got else 'FAIL')
    # $sync with an http peer sends its bearer token in clear; with a
    # self-signed https peer it must refuse the handshake.
    for peer, label in [('http://127.0.0.1:%d' % HOOK, 'http peer'),
                        ('https://127.0.0.1:%d' % TLS_PEER,
                         'self-signed https peer')]:
        RECEIVED.clear()
        s, _, b = r('POST', '/$sync', {
            'resourceType': 'Parameters', 'parameter': [
                {'name': 'peer', 'valueString': peer},
                {'name': 'token', 'valueString': 'peer-token-probe'}]})
        time.sleep(4)
        st, _, sb = r('GET', '/$sync-status')
        port = HOOK if label == 'http peer' else TLS_PEER
        got = [x for x in RECEIVED if x[0] == port]
        log('V12.3.1' if label == 'http peer' else 'V12.3.2',
            '$sync, ' + label, (s, 'peer saw %d requests' % len(got),
                                st, sb[:160]),
            ('FINDING' if got else 'NOTE') if label == 'http peer'
            else ('PASS' if not got else 'FAIL'))
        for _ in range(20):
            if r('GET', '/$sync-status')[0] != 202:
                break
            time.sleep(1)
    return backup


def run_y(backup):
    # V10.3.3: does a token name a user that cannot be reassigned? X and Y
    # share a secret. On X, root is 1 and the next account 2; Y gets its
    # own account 2 first, then restores X's backup.
    on(PX)
    rootx, _ = g.login(g.ROOT[0], g.ROOT[1], g.ROOT_IP)
    s, _, b = g.req('GET', '/admin/users', None, rootx, ip=ip())
    xusers = {u['username']: u['id'] for u in json.loads(b)['users']}
    nora_tok = g.login('nora', 'Nora-Long-Passw0rd!', ip())[0]
    # cara was in X's backup and was made admin on X after it.
    cara_tok = g.login('cara', 'Cara-Long-Passw0rd!', ip())[0]
    log('V10.3.3', 'accounts on X: count, nora', (len(xusers),
                                                   xusers['nora']), 'NOTE')
    on(PY)
    rooty, _ = g.login(g.ROOT[0], g.ROOT[1], g.ROOT_IP)
    s, _, b = g.req('GET', '/Patient', None, rootx, ip=ip())
    log('V10.3.1', "X's admin token at Y (shared secret)", s,
        'FINDING' if s == 200 else 'PASS')
    made = {}
    for name in sorted(xusers, key=xusers.get):
        if name == g.ROOT[0]:
            continue
        uid, _ = account(rooty, 'y-' + name, 'Y-Long-Passw0rd-%s!' % name)
        made[name] = uid
    s, _, b = raw('POST', '/$restore', backup,
                  {'Content-Type': 'application/vnd.sqlite3',
                   'x-backup-passphrase': 'probe-passphrase-1'},
                  token=rooty)
    log('V10.3.3', '$restore of X into Y', (s, b[:160]), 'NOTE')
    s, _, b = g.req('GET', '/admin/users', None, rooty, ip=ip())
    yusers = {u['username']: u['id'] for u in json.loads(b)['users']}
    log('V10.3.3', 'accounts on Y after restore: count, nora, y-nora',
        (len(yusers), yusers.get('nora'), yusers.get('y-nora')), 'NOTE')
    nora_x, nora_y = xusers['nora'], yusers.get('nora')
    holder = [n for n, i in yusers.items() if i == nora_x]
    s1, _, _ = g.req('GET', '/Observation', None, nora_tok, ip=ip())
    log('V10.3.3', "nora's X token at Y: X id %s, Y id %s, Y's id %s is %s"
        % (nora_x, nora_y, nora_x, holder), s1,
        'FINDING' if s1 == 200 and holder != ['nora'] else 'PASS')
    cara_y = yusers.get('cara')
    cara_holder = [n for n, i in yusers.items() if i == xusers['cara']]
    s4, _, b4 = g.req('GET', '/admin/users', None, cara_tok, ip=ip())
    log('V10.3.3', "cara (restored) X token at Y: X id %s, restored as Y id "
        "%s, Y's id %s is %s; GET /admin/users" % (
            xusers['cara'], cara_y, xusers['cara'], cara_holder), s4,
        'FINDING' if s4 == 200 and cara_holder != ['cara'] else 'PASS')
    if nora_y is not None and holder != ['nora']:
        g.req('POST', '/admin/users/%d/deactivate' % nora_y, {}, rooty,
              ip=ip())
        s2, _, _ = g.req('GET', '/Observation', None, nora_tok, ip=ip())
        log('V10.3.3', "nora deactivated on Y; her X token at Y", s2,
            'FINDING' if s2 == 200 else 'PASS')
        if holder:
            g.req('POST', '/admin/users/%d/deactivate' % nora_x, {}, rooty,
                  ip=ip())
            s3, _, _ = g.req('GET', '/Observation', None, nora_tok, ip=ip())
            log('V10.3.3', "%s (Y id %s) deactivated; nora's X token at Y"
                % (holder[0], nora_x), s3,
                'FINDING' if s3 == 401 else 'NOTE')


def run_z(work):
    on(PZ)
    d = os.path.join(work, 'z', 'db')
    found = []
    for root, _, files in os.walk(d):
        for f in files:
            if 'secret' in f or f.startswith('.jwt'):
                p = os.path.join(root, f)
                found.append((os.path.relpath(p, work),
                              oct(stat.S_IMODE(os.stat(p).st_mode))))
    log('V13.3.2', 'generated secret file and its mode', found,
        'PASS' if found and all(m == '0o600' for _, m in found) else 'FAIL')
    dirmode = oct(stat.S_IMODE(os.stat(d).st_mode))
    files = sorted((f, oct(stat.S_IMODE(os.stat(os.path.join(d, f))
                                         .st_mode))) for f in os.listdir(d))
    log('V13.3.2', 'store directory and its files', (dirmode, files),
        'NOTE')
    with open(os.path.join(work, 'x', 'pid')) as f:
        pid = f.read().strip()
    envmode = oct(stat.S_IMODE(os.stat('/proc/%s/environ' % pid).st_mode)) \
        if os.path.exists('/proc/%s/environ' % pid) else 'gone'
    log('V13.3.2', 'X (key in its environment): /proc/<pid>/environ mode',
        envmode, 'NOTE')


if __name__ == '__main__':
    main()
