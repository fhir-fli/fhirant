#!/usr/bin/env python3
"""Second look at subscription_probes FAIL/NOTE rows. Writes
subscription_followups.tsv.
Run: python3 -I tool/review_2026-10-17/subscription_followups.py <server> <workdir>"""
import http.server, json, os, shutil, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g
import subscription_probes as sp
OUT = os.path.join(g.HERE, 'subscription_followups.tsv')
def log(*c):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400] for x in c)
    with open(OUT, 'a') as f:
        f.write(line + '\n'); f.flush()
    print(line, flush=True)
g.BIN, work = sys.argv[1], sys.argv[2]
open(OUT, 'w').write('case\tobserved\n')
srv = http.server.ThreadingHTTPServer(('127.0.0.1', sp.HOOK_PORT), sp.Hook)
threading.Thread(target=srv.serve_forever, daemon=True).start()
d = os.path.join(work, 'subf'); shutil.rmtree(d, ignore_errors=True)
shutil.copytree(os.path.join(work, 'seed'), d)
p = g.start(os.path.join(d, 'db'), d)
try:
    clin, _ = g.login('clin', g.PW, '127.0.7.1')
    adm, _ = g.login('adm2', g.PW, '127.0.7.2')
    r = lambda m, path, b=None, tok=None: g.req(m, path, b, tok or clin, None, ip='127.0.7.9')
    obs = {'resourceType': 'Observation', 'status': 'final', 'code': {'coding': [{'system': 'http://loinc.org', 'code': '2823-3'}]}, 'subject': {'reference': 'Patient/pat1'}}
    def sub(ch, tok, criteria='Observation?code=2823-3'):
        s, _, b = r('POST', '/Subscription', {'resourceType': 'Subscription', 'status': 'requested', 'reason': 'p', 'criteria': criteria, 'channel': ch}, tok)
        return s, json.loads(b)
    s, j = sub({'type': 'rest-hook', 'endpoint': 'http://127.0.0.1:%d/hook' % sp.HOOK_PORT, 'header': ['X-Probe: abc']}, adm)
    sp.RECEIVED.clear(); r('POST', '/Observation', obs)
    got = sp.wait_for(lambda x: x['path'] == '/hook')
    log('rest-hook headers received (all)', got[0]['headers'] if got else None)
    s, j = sub({'type': 'websocket'}, clin)
    log('websocket sub created', s, j.get('status'), j.get('id'))
    wsid = j.get('id')
    w = sp.WS(clin); w.send('bind ' + wsid); log('bind', w.recv())
    time.sleep(1)
    r('POST', '/Observation', obs)
    msgs = []
    for _ in range(4):
        m = w.recv(5)
        if m: msgs.append(m)
    log('ws messages after a matching create (20 s)', msgs)
    for crit in ['NotAType?x=1', 'Observation?code:bogusmod=1', 'Observation?not-a-param=1']:
        s, j = sub({'type': 'rest-hook', 'endpoint': 'http://127.0.0.1:%d/hook' % sp.HOOK_PORT}, adm, crit)
        log('criteria %s' % crit, s, j.get('status'), j.get('error'))
    s, j = sub({'type': 'rest-hook', 'endpoint': 'http://127.0.0.1:9/x'}, adm)
    dead = j['id']
    for i in range(6):
        r('POST', '/Observation', obs); time.sleep(1.5)
        _, _, b = r('GET', '/Subscription/' + dead, tok=adm); st = json.loads(b)
        log('dead endpoint after %d writes' % (i + 1), st.get('status'), st.get('error'))
finally:
    g.stop(p); srv.shutdown()
