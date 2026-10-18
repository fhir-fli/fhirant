#!/usr/bin/env python3
"""Every hosted package in the three pubspec.lock files, queried against
OSV (api.osv.dev, ecosystem Pub). Writes osv_check.tsv.
Run from the fhirant repo root: python3 -I packages/fhirant_server/tool/review_2026-10-17/osv_check.py"""
import json, os, re, sys, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
pk = {}
for lock in ['packages/fhirant_server/pubspec.lock', 'packages/fhirant_db/pubspec.lock', 'packages/fhirant/pubspec.lock']:
    txt = open(lock).read()
    for m in re.finditer(r'\n  ([a-z0-9_]+):\n(?:    .*\n)*?    source: hosted\n    version: "([^"]+)"', txt):
        pk.setdefault((m.group(1), m.group(2)), set()).add(lock.split('/')[1])
items = sorted(pk)
q = {'queries': [{'package': {'name': n, 'ecosystem': 'Pub'}, 'version': v} for n, v in items]}
req = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=json.dumps(q).encode(), headers={'Content-Type': 'application/json'})
res = json.load(urllib.request.urlopen(req, timeout=60))['results']
out = os.path.join(HERE, 'osv_check.tsv')
hits = 0
with open(out, 'w') as f:
    f.write('package\tversion\tused by\tadvisories\n')
    for (n, v), r in zip(items, res):
        ids = [x['id'] for x in r.get('vulns', [])]
        hits += bool(ids)
        f.write('%s\t%s\t%s\t%s\n' % (n, v, ','.join(sorted(pk[(n, v)])), ','.join(ids)))
print(len(items), 'package versions queried;', hits, 'with advisories ->', out, flush=True)
# Prove the probe finds a known positive: jose 0.3.x has GHSA-vm9r-h74p-hg97 (memory: dep-refresh-2026-06).
ctl = json.load(urllib.request.urlopen(urllib.request.Request('https://api.osv.dev/v1/query', data=json.dumps({'package': {'name': 'jose', 'ecosystem': 'Pub'}, 'version': '0.3.2'}).encode(), headers={'Content-Type': 'application/json'}), timeout=60))
print('control jose 0.3.2:', [x['id'] for x in ctl.get('vulns', [])], flush=True)
