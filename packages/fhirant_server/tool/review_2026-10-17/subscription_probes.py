#!/usr/bin/env python3
"""R4B subscription.html probes (fifth fhirant review, 2026-10-17).

A local HTTP listener records what the server sends; a minimal websocket
client binds over /ws. One row per case to subscription_probes.tsv.

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/subscription_probes.py <server> <workdir>
"""
import base64
import http.server
import json
import os
import shutil
import socket
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'subscription_probes.tsv')
HOOK_PORT = 18490
RECEIVED = []


def log(*c):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in c)
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


class Hook(http.server.BaseHTTPRequestHandler):
    def _any(self):
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n).decode('utf-8', 'replace') if n else ''
        RECEIVED.append({'method': self.command, 'path': self.path,
                         'headers': dict(self.headers), 'body': body,
                         't': time.time()})
        self.send_response(200)
        self.send_header('Content-Length', '0')
        self.end_headers()
    do_POST = do_PUT = do_GET = _any

    def log_message(self, *a):
        pass


def wait_for(pred, secs=15):
    end = time.time() + secs
    while time.time() < end:
        hit = [x for x in RECEIVED if pred(x)]
        if hit:
            return hit
        time.sleep(0.25)
    return []


class WS:
    """Just enough RFC 6455 for text frames."""

    def __init__(self, token):
        self.s = socket.create_connection(('127.0.0.1', g.PORT), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        req = ('GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n'
               'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n'
               'Sec-WebSocket-Version: 13\r\nX-Forwarded-For: 1.1.1.1\r\n'
               % key)
        if token:
            req += 'Authorization: Bearer %s\r\n' % token
        self.s.sendall((req + '\r\n').encode())
        head = b''
        while b'\r\n\r\n' not in head:
            chunk = self.s.recv(1)
            if not chunk:
                break
            head += chunk
        self.status = head.split(b' ')[1].decode() if head else 'none'

    def send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        hdr = bytes([0x81, 0x80 | len(data)]) + mask
        self.s.sendall(hdr + bytes(b ^ mask[i % 4] for i, b in
                                   enumerate(data)))

    def recv(self, timeout=5):
        self.s.settimeout(timeout)
        try:
            h = self._n(2)
            ln = h[1] & 0x7f
            if ln == 126:
                ln = int.from_bytes(self._n(2), 'big')
            return self._n(ln).decode('utf-8', 'replace')
        except (socket.timeout, OSError):
            return None

    def _n(self, n):
        b = b''
        while len(b) < n:
            c = self.s.recv(n - len(b))
            if not c:
                raise OSError('closed')
            b += c
        return b


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\tobserved\tverdict\n')
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', HOOK_PORT), Hook)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    d = os.path.join(work, 'subscription')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        run()
    finally:
        g.stop(p)
        srv.shutdown()


def run():
    clin, _ = g.login('clin', g.PW, '127.0.6.1')
    other, _ = g.login('narrow', g.PW, '127.0.6.2')
    adm, _ = g.login('adm2', g.PW, '127.0.6.3')

    def r(m, path, b=None, tok=None, h=None):
        return g.req(m, path, b, tok or clin, h, ip='127.0.6.9')

    def sub(channel, criteria='Observation?code=2823-3', **extra):
        body = {'resourceType': 'Subscription', 'status': 'requested',
                'reason': 'probe', 'criteria': criteria, 'channel': channel}
        body.update(extra)
        # rest-hook is system authority (request_authorization.dart);
        # websocket and the rest are a client's own.
        tok = adm if channel.get('type') == 'rest-hook' else clin
        return r('POST', '/Subscription', body, tok)

    def obs(value, code='2823-3'):
        return {'resourceType': 'Observation', 'status': 'final',
                'code': {'coding': [{'system': 'http://loinc.org',
                                     'code': code}]},
                'subject': {'reference': 'Patient/pat1'},
                'valueQuantity': {'value': value}}

    hook = 'http://127.0.0.1:%d/hook' % HOOK_PORT
    s, h, b = sub({'type': 'rest-hook', 'endpoint': hook,
                   'header': ['X-Probe: abc']})
    j = json.loads(b)
    sid = j.get('id')
    log('create rest-hook', (s, j.get('status')), 'PASS' if s == 201 and
        j.get('status') == 'active' else 'FAIL')
    RECEIVED.clear()
    s, _, b = r('POST', '/Observation', obs(3.9))
    oid = json.loads(b)['id']
    got = wait_for(lambda x: x['path'] == '/hook')
    log('notify on create (empty POST)', [(x['method'], len(x['body']))
                                          for x in got],
        'PASS' if got and got[0]['method'] == 'POST' and not got[0]['body']
        else 'FAIL')
    log('channel.header appended', [x['headers'].get('X-Probe')
                                     for x in got],
        'PASS' if got and got[0]['headers'].get('X-Probe') == 'abc'
        else 'FAIL')
    RECEIVED.clear()
    r('PUT', '/Observation/' + oid, dict(obs(4.0), id=oid))
    got = wait_for(lambda x: x['path'] == '/hook')
    log('notify on update', len(got), 'PASS' if got else 'FAIL')
    RECEIVED.clear()
    r('PUT', '/Observation/' + oid, dict(obs(4.0, code='8867-4'), id=oid))
    got = wait_for(lambda x: x['path'] == '/hook', 4)
    log('no notify when update stops matching', len(got),
        'PASS' if not got else 'FAIL')
    RECEIVED.clear()
    r('DELETE', '/Observation/' + oid)
    got = wait_for(lambda x: x['path'] == '/hook', 4)
    log('no notify on delete', len(got), 'PASS' if not got else 'FAIL')

    # Payload: a PUT of the resource to [endpoint]/[type]/[id].
    s, _, b = sub({'type': 'rest-hook', 'endpoint': 'http://127.0.0.1:%d/'
                   'fhir' % HOOK_PORT, 'payload': 'application/fhir+json'})
    RECEIVED.clear()
    s, _, b = r('POST', '/Observation', obs(5.1))
    oid2 = json.loads(b)['id']
    got = wait_for(lambda x: x['path'].startswith('/fhir'))
    log('payload as update to [base]/[type]/[id]',
        [(x['method'], x['path'], x['body'][:60]) for x in got],
        'PASS' if got and got[0]['method'] == 'PUT' and
        got[0]['path'] == '/fhir/Observation/' + oid2 else 'FAIL')

    # Channels the server cannot execute.
    for ch in [{'type': 'email', 'endpoint': 'mailto:x@example.org'},
               {'type': 'sms', 'endpoint': 'tel:+15555555555'},
               {'type': 'message', 'endpoint': 'http://127.0.0.1:9/$process-'
                'message'}]:
        s, _, b = sub(ch)
        log('unsupported channel %s' % ch['type'], (s, json.loads(b).get(
            'status') if s < 300 else b[:140]),
            'PASS' if s >= 400 and 'OperationOutcome' in b else 'FAIL')
    s, _, b = sub({'type': 'rest-hook', 'endpoint': hook},
                  criteria='NotAType?x=1')
    log('criteria unknown type', (s, b[:140]),
        'PASS' if s >= 400 else 'FAIL')
    s, _, b = sub({'type': 'rest-hook', 'endpoint': hook},
                  criteria='Observation?not-a-param=1')
    log('criteria unknown param', (s, b[:140]), 'NOTE')
    s, _, b = sub({'type': 'rest-hook', 'endpoint': hook},
                  criteria='Observation?code:bogusmod=1')
    log('criteria bad modifier', (s, b[:140]),
        'PASS' if s >= 400 else 'FAIL')

    # Failure handling: an endpoint nobody answers.
    s, _, b = sub({'type': 'rest-hook', 'endpoint': 'http://127.0.0.1:9/x'})
    dead = json.loads(b).get('id')
    r('POST', '/Observation', obs(5.2))
    st = None
    for _ in range(40):
        _, _, b = r('GET', '/Subscription/%s' % dead, tok=adm)
        st = json.loads(b)
        if st.get('status') == 'error':
            break
        time.sleep(0.5)
    log('failed delivery sets status error + error', (st.get('status'),
                                                      st.get('error')),
        'PASS' if st.get('status') == 'error' and st.get('error')
        else 'FAIL')

    # Endpoint allow-list (subscription.html 2.46.5: "a server might maintain
    # a whitelist of acceptable servers"): what will it accept?
    for ep in ['http://169.254.169.254/latest/meta-data/',
               'http://10.0.0.1/x', 'file:///etc/passwd', 'ftp://x/y',
               'http://[::1]:9/x']:
        s, _, b = sub({'type': 'rest-hook', 'endpoint': ep})
        log('endpoint accepted: %s' % ep, (s, json.loads(b).get('status')
                                           if s < 300 else b[:120]), 'NOTE')

    # end date
    soon = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + 3))
    s, _, b = sub({'type': 'rest-hook', 'endpoint': hook}, end=soon)
    eid = json.loads(b).get('id')
    time.sleep(5)
    RECEIVED.clear()
    r('POST', '/Observation', obs(5.3))
    time.sleep(3)
    s2, _, b2 = r('GET', '/Subscription/%s' % eid, tok=adm)
    sent = [x for x in RECEIVED if x['path'] == '/hook']
    log('past end: deleted / not notified', (s2, json.loads(b2).get('status')
                                             if s2 == 200 else '', len(sent)),
        'NOTE')
    past = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 60))
    s, _, b = sub({'type': 'rest-hook', 'endpoint': hook}, end=past)
    log('create with end in the past', (s, b[:140]), 'NOTE')

    # Websocket: bind to one's own and to another account's subscription.
    s, _, b = sub({'type': 'websocket'})
    wsid = json.loads(b).get('id')
    w0 = WS(None)
    log('ws upgrade without token', w0.status,
        'PASS' if w0.status == '401' else 'FAIL')
    w1 = WS(clin)
    log('ws upgrade with token', w1.status,
        'PASS' if w1.status == '101' else 'FAIL')
    w1.send('bind ' + wsid)
    log('ws bind own', w1.recv(), 'NOTE')
    w2 = WS(other)
    w2.send('bind ' + wsid)
    ans = w2.recv()
    log("ws bind another account's subscription", ans,
        'FAIL' if ans and ans.startswith('bound') else 'PASS')
    w3 = WS(clin)
    w3.send('bind does-not-exist')
    log('ws bind unknown id', w3.recv(), 'NOTE')
    r('POST', '/Observation', obs(5.4))
    log('ws ping own', w1.recv(8), 'NOTE')
    log('ws ping on the other account', w2.recv(3),
        'NOTE')

    # Audit of notifications (encouraged).
    _, _, b = r('GET', '/AuditEvent?_count=200', tok=adm)
    kinds = {}
    for e in json.loads(b).get('entry', []):
        a = e['resource']
        k = (a.get('type', {}).get('code'),
             (a.get('subtype') or [{}])[0].get('code'))
        kinds[k] = kinds.get(k, 0) + 1
    log('AuditEvent kinds after notifications', sorted(kinds.items(),
                                                       key=str), 'NOTE')

    # Who can see subscriptions (and their channel headers)?
    _, _, b = r('GET', '/Subscription', tok=other)
    log("another clinician's search sees the first one's channel.header",
        'X-Probe' in b, 'NOTE')


if __name__ == '__main__':
    main()
