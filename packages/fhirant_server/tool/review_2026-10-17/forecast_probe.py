#!/usr/bin/env python3
"""Forecast answers for a patient with and without a birthDate, and a
Parameters body naming no patient. Writes forecast_probe.tsv.
Run: python3 -I tool/review_2026-10-17/forecast_probe.py <server> <workdir>"""
import json, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g
OUT = os.path.join(g.HERE, 'forecast_probe.tsv')
def log(*c):
    with open(OUT, 'a') as f:
        f.write('\t'.join(str(x) for x in c) + '\n'); f.flush()
    print(*c, sep='\t', flush=True)
g.BIN, work = sys.argv[1], sys.argv[2]
open(OUT, 'w').write('case\tstatus\tparameter names\trecommendations\n')
d = os.path.join(work, 'forecast'); shutil.rmtree(d, ignore_errors=True)
shutil.copytree(os.path.join(work, 'seed'), d)
p = g.start(os.path.join(d, 'db'), d)
try:
    root, _ = g.login(*g.ROOT, ip=g.ROOT_IP)
    g.req('PUT', '/Patient/fc1', {'resourceType': 'Patient', 'id': 'fc1', 'birthDate': '2025-01-01'}, root, ip=g.ROOT_IP)
    cases = [('patientId pat2 (no birthDate)', {'patientId': 'pat2', 'assessmentDate': '2026-10-17'}),
             ('patientId fc1 (birthDate 2025-01-01)', {'patientId': 'fc1', 'assessmentDate': '2026-10-17'}),
             ('Parameters, no patient', {'resourceType': 'Parameters', 'parameter': [{'name': 'assessmentDate', 'valueDate': '2026-10-17'}]}),
             ('Parameters, patient resource without birthDate', {'resourceType': 'Parameters', 'parameter': [{'name': 'assessmentDate', 'valueDate': '2026-10-17'}, {'name': 'patient', 'resource': {'resourceType': 'Patient', 'id': 'x'}}]})]
    for op in ['$immds-forecast', '$immds-forecast-who']:
        for name, body in cases:
            s, _, b = g.req('POST', '/' + op, body, root, ip=g.ROOT_IP)
            try:
                j = json.loads(b)
                names = [x['name'] for x in j.get('parameter', [])]
                recs = sum(len(x['resource'].get('recommendation', [])) for x in j.get('parameter', []) if x['name'] == 'recommendation')
            except Exception:
                names, recs = b[:120], '-'
            log(op + ' ' + name, s, ','.join(names) if isinstance(names, list) else names, recs)
finally:
    g.stop(p)
