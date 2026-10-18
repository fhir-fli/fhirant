#!/usr/bin/env python3
"""Bulk Data Access STU2 export.html probes (fifth fhirant review,
2026-10-17). One row per case to bulk_probes.tsv.

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/bulk_probes.py <server> <workdir>
"""
import json
import os
import shutil
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'bulk_probes.tsv')
T = None
ASYNC = {'Prefer': 'respond-async', 'Accept': 'application/fhir+json'}


def log(case, rule, expected, observed, verdict):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in (case, rule, expected, observed, verdict))
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def r(m, path, body=None, headers=None, tok='T'):
    return g.req(m, path, body, T if tok == 'T' else tok, headers,
                 ip=g.ROOT_IP)


def hget(h, k):
    for a, b in h.items():
        if a.lower() == k.lower():
            return b
    return None


def kick(path, headers=None, body=None, method='GET'):
    s, h, b = r(method, path, body, dict(ASYNC, **(headers or {})))
    loc = hget(h, 'Content-Location')
    return s, h, b, loc


def poll(loc, secs=60):
    path = '/' + loc.split('/', 3)[-1] if loc.startswith('http') else loc
    first = None
    for _ in range(secs * 2):
        s, h, b = r('GET', path, headers={'Accept': 'application/json'})
        if first is None:
            first = (s, hget(h, 'Retry-After'), hget(h, 'X-Progress'))
        if s != 202:
            return s, h, b, first, path
        time.sleep(0.5)
    return s, h, b, first, path


def files(manifest):
    """{type: [resources]} from a complete manifest."""
    out = {}
    for o in manifest.get('output', []):
        u = urllib.parse.urlsplit(o['url'])
        s, h, b = r('GET', u.path, headers={'Accept': '*/*'})
        rows = [json.loads(x) for x in b.splitlines() if x.strip()]
        out.setdefault(o['type'], []).extend(rows)
        out.setdefault('_ctype', []).append(hget(h, 'Content-Type'))
        out.setdefault('_mixed', []).append(
            sorted({x.get('resourceType') for x in rows}))
    return out


def main():
    global T
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\trule\texpected\tobserved\tverdict\n')
    d = os.path.join(work, 'bulk')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        T, _ = g.login('adm2', g.PW, g.ROOT_IP)
        run()
    finally:
        g.stop(p)


def run():
    # Fixtures: a patient outside g1, a Provenance about pat1's Observation,
    # an updated Observation (two versions), a deleted one, a Binary.
    r('PUT', '/Patient/pat3', {'resourceType': 'Patient', 'id': 'pat3',
                               'name': [{'family': 'NotInGroup'}]})
    r('PUT', '/Observation/obs3', {'resourceType': 'Observation',
                                   'id': 'obs3', 'status': 'final',
                                   'code': {'text': 'NOTINGROUP'},
                                   'subject': {'reference': 'Patient/pat3'}})
    r('PUT', '/Provenance/prov1', {'resourceType': 'Provenance', 'id': 'prov1',
                                   'target': [{'reference':
                                               'Observation/obs1'}],
                                   'recorded': '2026-10-17T00:00:00Z',
                                   'agent': [{'who': {'display': 'lab'}}]})
    r('PUT', '/Observation/obs1', {'resourceType': 'Observation', 'id': 'obs1',
                                   'status': 'amended', 'code': {'text':
                                                                 'v2'},
                                   'subject': {'reference': 'Patient/pat1'}})
    r('PUT', '/Observation/gone', {'resourceType': 'Observation', 'id': 'gone',
                                   'status': 'final', 'code': {'text': 'g'},
                                   'subject': {'reference': 'Patient/pat1'}})
    r('DELETE', '/Observation/gone')
    r('PUT', '/Binary/b1', {'resourceType': 'Binary', 'id': 'b1',
                            'contentType': 'text/plain', 'data': 'aGk=',
                            'securityContext': {'reference':
                                                'Patient/pat1'}})

    # Kick-off
    s, h, b, loc = kick('/$export')
    log('kick-off GET', 'A server SHALL support GET requests', '202 + '
        'Content-Location', (s, loc), 'PASS' if s == 202 and loc else 'FAIL')
    s, ph, pb, first, ppath = poll(loc)
    log('in-progress status', 'A server SHOULD supply a Retry-After header',
        'Retry-After on 202', first, 'PASS' if first and first[0] == 202 and
        first[1] else ('NOTE' if first and first[0] != 202 else 'FAIL'))
    m = json.loads(pb) if s == 200 else {}
    log('complete manifest', 'transactionTime, request, requiresAccessToken, '
        'output[type,url], error', 'all keys', (s, sorted(m.keys())),
        'PASS' if s == 200 and all(k in m for k in (
            'transactionTime', 'request', 'requiresAccessToken', 'output',
            'error')) else 'FAIL')
    log('Expires header', 'The server SHOULD return an Expires header',
        'present', hget(ph, 'Expires'), 'PASS' if hget(ph, 'Expires')
        else 'FAIL')
    log('requiresAccessToken', 'Value SHALL be true if both the file server '
        'and the FHIR API server control access using OAuth 2.0 bearer '
        'tokens', True, m.get('requiresAccessToken'),
        'PASS' if m.get('requiresAccessToken') is True else 'FAIL')
    f = files(m)
    log('file Content-Type', 'For files in ndjson format, SHALL be '
        'application/fhir+ndjson', 'all application/fhir+ndjson',
        sorted(set(f.get('_ctype', []))),
        'PASS' if f.get('_ctype') and all(
            c and c.startswith('application/fhir+ndjson')
            for c in f['_ctype']) else 'FAIL')
    log('one type per file', 'Each file SHALL contain resources of only one '
        'type', 'one type each', f.get('_mixed'),
        'PASS' if all(len(x) == 1 for x in f.get('_mixed', [])) else 'FAIL')
    obs = {x['id']: x for x in f.get('Observation', [])}
    log('only the latest version', 'The exported data SHALL include only the '
        'most recent version', 'obs1 once, status amended',
        [(x['id'], x.get('status')) for x in f.get('Observation', [])
         if x['id'] == 'obs1'],
        'PASS' if [x for x in f.get('Observation', []) if x['id'] == 'obs1']
        == [obs.get('obs1')] and obs.get('obs1', {}).get('status') ==
        'amended' else 'FAIL')
    log('deleted not in output', "Resources that appear in the 'deleted' "
        "section ... SHALL NOT appear in 'output'", 'no Observation/gone',
        'gone' in obs, 'PASS' if 'gone' not in obs else 'FAIL')
    log('Binary associated with a patient', 'Binary Resources whose content '
        'is associated with an individual patient SHALL be serialized as '
        'DocumentReference', 'no Binary/b1 in system export, or as '
        'DocumentReference', (sorted(k for k in f if not k.startswith('_')),
                              [x['id'] for x in f.get('Binary', [])]),
        'NOTE')
    tt = m.get('transactionTime')
    # transactionTime semantics: anything modified up to it is included.
    log('transactionTime', 'SHALL include any matching resources modified up '
        'to and including this instant', 'present', tt,
        'PASS' if tt else 'FAIL')

    # DELETE then poll -> 404 + OperationOutcome
    s, h, b = r('DELETE', ppath)
    s2, h2, b2 = r('GET', ppath, headers={'Accept': 'application/json'})
    log('poll after DELETE', 'Following the delete request, when subsequent '
        'requests are made to the polling location, the server SHALL return a '
        '404 Not Found error and an associated FHIR OperationOutcome', '404 '
        'OO', (s, s2, b2[:100]), 'PASS' if s2 == 404 and 'OperationOutcome'
        in b2 else 'FAIL')
    for o in m.get('output', [])[:1]:
        u = urllib.parse.urlsplit(o['url'])
        s3, _, _ = r('GET', u.path, headers={'Accept': '*/*'})
        log('file after DELETE', 'a server MAY use the request as a signal '
            'that it is safe to remove those from storage', 'read', s3,
            'NOTE')

    # _outputFormat
    for fmt in ['application/fhir+ndjson', 'application/ndjson', 'ndjson',
                'text/csv']:
        s, h, b, loc = kick('/$export?_type=Patient&_outputFormat=' +
                            urllib.parse.quote(fmt))
        log('_outputFormat=%s' % fmt, 'The server SHALL accept the full '
            'content type of application/fhir+ndjson as well as the '
            'abbreviated representations application/ndjson and ndjson',
            '202' if fmt != 'text/csv' else '4xx', (s, b[:100]),
            'PASS' if (s == 202) == (fmt != 'text/csv') else 'FAIL')
        if loc:
            r('DELETE', poll(loc)[4])
    # _type, repeated
    s, h, b, loc = kick('/$export?_type=Patient&_type=Group')
    s2, _, pb, _, path = poll(loc)
    types = sorted(o['type'] for o in json.loads(pb).get('output', [])) \
        if s2 == 200 else pb[:100]
    log('repeated _type', 'The server SHALL treat the values provided as if '
        'they were comma delimited values within a single instance',
        "['Group', 'Patient']", types,
        'PASS' if types == ['Group', 'Patient'] else 'FAIL')
    r('DELETE', path)
    s, h, b, loc = kick('/$export?_type=NotAType')
    log('_type unknown', 'the server SHOULD return details via a FHIR '
        'OperationOutcome resource in an error response', '4xx OO',
        (s, b[:120]), 'PASS' if s >= 400 and 'OperationOutcome' in b
        else 'FAIL')
    # _since
    time.sleep(1.1)
    since = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    time.sleep(1.1)
    r('PUT', '/Observation/obs2', {'resourceType': 'Observation', 'id': 'obs2',
                                   'status': 'amended', 'code': {'text':
                                                                 'after'},
                                   'subject': {'reference': 'Patient/pat2'}})
    s, h, b, loc = kick('/$export?_type=Observation&_since=' + since)
    s2, _, pb, _, path = poll(loc)
    got = files(json.loads(pb)) if s2 == 200 else {}
    ids = sorted(x['id'] for x in got.get('Observation', []))
    log('_since', 'Resources will be included in the response if their state '
        'has changed after the supplied time', "['obs2']", ids,
        'PASS' if ids == ['obs2'] else 'FAIL')
    log('_since deleted array', 'When a _since timestamp is supplied ... this '
        'array SHOULD be populated', 'read', json.loads(pb).get('deleted')
        if s2 == 200 else None, 'NOTE')
    r('DELETE', path)
    # Group export: members only
    s, h, b, loc = kick('/Group/g1/$export')
    s2, _, pb, _, path = poll(loc)
    got = files(json.loads(pb)) if s2 == 200 else {}
    pids = sorted(x['id'] for x in got.get('Patient', []))
    oids = sorted(x['id'] for x in got.get('Observation', []))
    log('Group export members only', 'compartments of the group members',
        'pat1, pat2 only; no obs3', (pids, oids),
        'PASS' if 'pat3' not in pids and 'obs3' not in oids and pids
        else 'FAIL')
    log('Provenance in Group/Patient export', 'the server SHALL include all '
        'available Provenance resources whose Provenance.target is a resource '
        'in the Patient compartment', 'prov1',
        [x['id'] for x in got.get('Provenance', [])],
        'PASS' if [x['id'] for x in got.get('Provenance', [])] == ['prov1']
        else 'FAIL')
    r('DELETE', path)
    s, h, b, loc = kick('/Patient/$export')
    s2, _, pb, _, path = poll(loc)
    got = files(json.loads(pb)) if s2 == 200 else {}
    log('Provenance in Patient export', 'SHALL include all available '
        'Provenance ... in a patient level export request', 'prov1',
        [x['id'] for x in got.get('Provenance', [])],
        'PASS' if 'prov1' in [x['id'] for x in got.get('Provenance', [])]
        else 'FAIL')
    log('Binary in Patient export', 'SHALL be serialized as '
        'DocumentReference', 'no raw Binary/b1',
        ([x['id'] for x in got.get('Binary', [])],
         len(got.get('DocumentReference', []))),
        'PASS' if not got.get('Binary') else 'FAIL')
    r('DELETE', path)
    # patient parameter (POST)
    s, h, b, loc = kick('/Patient/$export', method='POST', body={
        'resourceType': 'Parameters', 'parameter': [
            {'name': 'patient', 'valueReference': {'reference':
                                                   'Patient/pat1'}}]})
    if s == 202:
        s2, _, pb, _, path = poll(loc)
        got = files(json.loads(pb)) if s2 == 200 else {}
        log('patient parameter', 'the server SHALL NOT return resources in '
            'the patient compartments belonging to patients outside of this '
            'list', 'pat1 only', sorted(x['id'] for x in
                                        got.get('Patient', [])),
            'PASS' if sorted(x['id'] for x in got.get('Patient', []))
            == ['pat1'] else 'FAIL')
        r('DELETE', path)
    else:
        log('patient parameter (POST kick-off)', 'MAY support POST; a server '
            'unable to support patient SHOULD return an error and OO',
            '202 or 4xx OO', (s, b[:120]),
            'PASS' if s >= 400 and 'OperationOutcome' in b else 'FAIL')
    s, h, b, loc = kick('/Patient/$export?patient=Patient/pat1')
    log('patient as GET param', 'patient: POST only in STU2', 'read',
        (s, b[:120]), 'NOTE')
    if loc:
        r('DELETE', poll(loc)[4])
    for q in ['_elements=Patient.id', '_typeFilter=Patient%3Factive%3Dtrue',
              'includeAssociatedData=LatestProvenanceResources',
              'notAParam=1']:
        s, h, b, loc = kick('/$export?_type=Patient&' + q)
        log('kick-off %s' % q.split('=')[0], 'A server unable to support it '
            'SHOULD return an error and OO', 'applied or 4xx', (s, b[:120]),
            'NOTE')
        if loc:
            s2, _, pb, _, path = poll(loc)
            if q.startswith('_elements') and s2 == 200:
                got = files(json.loads(pb))
                tags = [t.get('code') for x in got.get('Patient', [])
                        for t in x.get('meta', {}).get('tag', [])]
                keys = sorted({k for x in got.get('Patient', []) for k in x})
                log('_elements applied', 'SHOULD omit unlisted, non-mandatory '
                    'elements ... SHOULD mark SUBSETTED', 'id only + '
                    'SUBSETTED', (keys, sorted(set(tags))),
                    'PASS' if 'name' not in keys and 'SUBSETTED' in tags
                    else 'FAIL')
            r('DELETE', path)
    # Concurrent exports
    locs = []
    codes = []
    for _ in range(4):
        s, h, b, loc = kick('/$export')
        codes.append((s, hget(h, 'Retry-After')))
        if loc:
            locs.append(loc)
    log('concurrent kick-offs', 'it SHOULD respond with a 429 Too Many '
        'Requests status and a Retry-After header (if it limits)', 'read',
        codes, 'NOTE')
    for loc in locs:
        r('DELETE', poll(loc)[4])
    # No Prefer header
    s, h, b = r('GET', '/$export', headers={'Accept': 'application/fhir+json'})
    log('kick-off without Prefer', 'MAY return an error or MAY process',
        'read', (s, b[:100]), 'NOTE')


if __name__ == '__main__':
    main()
