#!/usr/bin/env python3
"""Times one Bundle of 500 PUTs of new MIMIC resources sent to a running
fhirant (dev mode) as a batch and as a transaction, alternating, three
rounds each. Usage: batch_vs_transaction.py PORT NDJSON_FILE OUT_TSV"""
import json, sys, time, urllib.request
port, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
lines = [json.loads(l) for l in open(src) if l.strip()][:3000]
fh = open(out, 'w'); fh.write('round\ttype\tentries\tseconds\tstatus_ok\n'); fh.flush()
for r in range(3):
    for kind in ('batch', 'transaction'):
        start = (r * 2 + (kind == 'transaction')) * 500
        chunk = lines[start:start + 500]
        body = {'resourceType': 'Bundle', 'type': kind, 'entry': [
            {'resource': x, 'request': {'method': 'PUT', 'url': f"{x['resourceType']}/{x['id']}"}}
            for x in chunk]}
        req = urllib.request.Request(f'http://localhost:{port}/', data=json.dumps(body).encode(),
            method='POST', headers={'content-type': 'application/fhir+json'})
        t = time.time()
        reply = json.load(urllib.request.urlopen(req, timeout=600))
        el = time.time() - t
        ok = sum(1 for e in reply.get('entry', []) if str(e['response']['status']).startswith('20'))
        fh.write(f'{r}\t{kind}\t{len(chunk)}\t{el:.2f}\t{ok}\n'); fh.flush()
        print(r, kind, f'{el:.2f}s', ok, flush=True)
