#!/usr/bin/env python3
"""Follow-up probes on the access grid's flagged rows (2026-10-17).

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/followups.py <server-binary> <workdir>
One line per case to followups.tsv.
"""
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'followups.tsv')


def log(*cols):
    line = '\t'.join(str(c) for c in cols)
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    seed = json.load(open(g.SEED_OUT))
    open(OUT, 'w').write('case\tresult\n')
    d = os.path.join(work, 'followups')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        root, _ = g.login(*g.ROOT, ip=g.ROOT_IP)
        pat, _ = g.login('pat', g.PW, '127.0.1.20')
        fil = '/$export-file/' + seed['file']

        # Export file: which Accept values does the download take?
        for acc in [None, 'application/fhir+ndjson', 'application/ndjson',
                    'application/fhir+json', '*/*']:
            h = {'Accept': acc} if acc else {}
            c = g.http.client.HTTPConnection('127.0.0.1', g.PORT,
                                             source_address=(g.ROOT_IP, 0))
            hdr = {'Authorization': 'Bearer ' + root}
            hdr.update(h)
            c.request('GET', fil, headers=hdr)
            r = c.getresponse()
            body = r.read()
            log('export-file Accept=%s' % acc, r.status,
                r.getheader('Content-Type'), len(body))
            c.close()
        # The same download with no credential and a spec Accept.
        s, _, _ = g.req('GET', fil, headers={'Accept': '*/*'})
        log('export-file no token Accept=*/*', s)

        # Patient scope: every resource in $everything and _history, by
        # type/id and its patient reference.
        for path in ['/Patient/pat1/$everything', '/_history?_count=100']:
            s, _, b = g.req('GET', path, token=pat)
            ids = [(e.get('resource') or {}).get('resourceType', '-') + '/' +
                   (e.get('resource') or {}).get('id', '-')
                   for e in json.loads(b).get('entry', [])]
            log('pat %s' % path, s, ' '.join(ids))
        # Conditional delete of another patient's Observation left it alone?
        s, _, b = g.req('GET', '/Observation/obs2b', token=root)
        log('obs2b after pat cond-delete (fresh store, control)', s)
        s, _, b = g.req('DELETE', '/Observation?identifier=urn:grid|obs2b',
                        token=pat)
        log('pat cond-delete obs2b', s, b[:160])
        s, _, b = g.req('GET', '/Observation/obs2b', token=root)
        log('obs2b after pat cond-delete', s)

        # Forecast: a well-formed request for a patient with no birthDate,
        # and one with a birthDate.
        for pid, bd in [('pat2', None), ('fc1', '2025-01-01')]:
            if bd:
                g.req('PUT', '/Patient/fc1', {'resourceType': 'Patient',
                                              'id': 'fc1', 'birthDate': bd},
                      root, ip=g.ROOT_IP)
            for op in ['$immds-forecast', '$immds-forecast-who']:
                s, _, b = g.req('POST', '/' + op,
                                {'patientId': pid,
                                 'assessmentDate': '2026-10-17'}, root,
                                ip=g.ROOT_IP)
                log('%s patientId=%s birthDate=%s' % (op, pid, bd), s,
                    b[:160])
    finally:
        g.stop(p)


if __name__ == '__main__':
    main()
