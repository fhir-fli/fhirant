#!/usr/bin/env python3
"""Is _typeFilter applied, or accepted and ignored? No seeded Patient has
active=true, so an applied filter exports zero Patients. Writes
bulk_typefilter_probe.tsv.
Run: python3 -I tool/review_2026-10-17/bulk_typefilter_probe.py <server> <workdir>"""
import json, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g
import bulk_probes as bp
OUT = os.path.join(g.HERE, 'bulk_typefilter_probe.tsv')
g.BIN, work = sys.argv[1], sys.argv[2]
d = os.path.join(work, 'bulktf'); shutil.rmtree(d, ignore_errors=True)
shutil.copytree(os.path.join(work, 'seed'), d)
p = g.start(os.path.join(d, 'db'), d)
try:
    bp.T, _ = g.login('adm2', g.PW, g.ROOT_IP)
    with open(OUT, 'w') as f:
        f.write('case\tpatients exported\n')
        for q in ['_type=Patient', '_type=Patient&_typeFilter=Patient%3Factive%3Dtrue', '_type=Patient&_typeFilter=Patient%3F_id%3Dpat1']:
            s, h, b, loc = bp.kick('/$export?' + q)
            s2, _, pb, _, path = bp.poll(loc)
            got = bp.files(json.loads(pb)) if s2 == 200 else {}
            line = '%s\t%s\n' % (q, sorted(x['id'] for x in got.get('Patient', [])))
            f.write(line); f.flush(); print(line, end='', flush=True)
finally:
    g.stop(p)
