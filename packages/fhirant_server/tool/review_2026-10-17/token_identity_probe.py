#!/usr/bin/env python3
"""Are two sessions minted in the same second the same token? If so, ending
one ends the other, and a refresh rotated twice in a second hands back a
token already revoked. Writes token_identity_probe.tsv.
Run: python3 -I tool/review_2026-10-17/token_identity_probe.py <server> <workdir>"""
import json, os, shutil, sys, time, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g
OUT = os.path.join(g.HERE, 'token_identity_probe.tsv')
def log(*c):
    line = '\t'.join(str(x).replace('\t', ' ')[:300] for x in c)
    with open(OUT, 'a') as f:
        f.write(line + '\n'); f.flush()
    print(line, flush=True)
g.BIN, work = sys.argv[1], sys.argv[2]
open(OUT, 'w').write('case\tobserved\n')
d = os.path.join(work, 'tokid'); shutil.rmtree(d, ignore_errors=True)
shutil.copytree(os.path.join(work, 'seed'), d)
p = g.start(os.path.join(d, 'db'), d)
try:
    same = 0
    for trial in range(5):
        # Two devices, same account, logging in within one second.
        a1, r1 = g.login('clin', g.PW, '127.0.9.%d' % (2 * trial + 1))
        a2, r2 = g.login('clin', g.PW, '127.0.9.%d' % (2 * trial + 2))
        if a1 == a2:
            same += 1
            s, _, _ = g.req('POST', '/auth/logout', {'refresh_token': r1}, a1, ip='127.0.9.50')
            s2, _, b2 = g.req('GET', '/Patient/pat1', token=a2, ip='127.0.9.51')
            log('trial %d: identical tokens; device 1 logs out, device 2 read' % trial, s, s2, b2[:100])
            break
        time.sleep(0.3)
    log('identical access tokens in 5 paired logins', same)
    # Refresh twice within a second.
    a, r = g.login('pat', g.PW, '127.0.9.60')
    s1, _, b1 = g.req('POST', '/auth/token', 'grant_type=refresh_token&refresh_token=' + r, ip='127.0.9.61')
    j1 = json.loads(b1)
    log('refresh 1', s1, 'new refresh == old:', j1.get('refresh_token') == r)
    s2, _, b2 = g.req('POST', '/auth/token', 'grant_type=refresh_token&refresh_token=' + j1.get('refresh_token', ''), ip='127.0.9.62')
    log('refresh 2 with the token refresh 1 returned (same second)', s2, b2[:120])
    time.sleep(1.2)
    a, r = g.login('rdonly', g.PW, '127.0.9.63')
    time.sleep(1.2)
    s1, _, b1 = g.req('POST', '/auth/token', 'grant_type=refresh_token&refresh_token=' + r, ip='127.0.9.64')
    j1 = json.loads(b1)
    time.sleep(1.2)
    s2, _, b2 = g.req('POST', '/auth/token', 'grant_type=refresh_token&refresh_token=' + j1.get('refresh_token', ''), ip='127.0.9.65')
    log('control: same with 1.2 s between steps', s1, s2, b2[:80])
finally:
    g.stop(p)
