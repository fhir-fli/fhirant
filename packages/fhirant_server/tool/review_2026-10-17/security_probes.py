#!/usr/bin/env python3
"""R4B security.html probes (fifth fhirant review, 2026-10-17).

security.html 6.1.0.5.1 "Access Control Considerations" lists the ways a
client can reach a resource besides a plain read: chained search, _include
and _revinclude, container resources (Bundle, Composition, Group, List),
operations that disclose patient data ($everything ...), and batch /
transaction entries. Each is probed here with an account whose scopes
cover ONE resource type, so a resource of any other type in the answer is
a disclosure the scopes did not grant. Plus 6.1.0.3 (error detail to
unauthorised clients), 6.1.0.9 (active content in narrative; user content
served as text/html).

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/security_probes.py <server> <workdir>
"""
import base64
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'security_probes.tsv')


def log(*c):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in c)
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def types_in(body):
    """Every resourceType in a Bundle's entries (one level)."""
    try:
        j = json.loads(body)
    except ValueError:
        return None
    if j.get('resourceType') != 'Bundle':
        return [j.get('resourceType')]
    return sorted({(e.get('resource') or {}).get('resourceType', '-')
                   for e in j.get('entry', [])})


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\tscopes\tstatus\ttypes or detail\tverdict\n')
    d = os.path.join(work, 'security')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        adm, _ = g.login('adm2', g.PW, g.ROOT_IP)
        accounts = {
            'obsonly': ['user/Observation.rs'],
            'componly': ['user/Composition.rs'],
            'patonly': ['user/Patient.rs'],
            'grouponly': ['user/Group.rs'],
            'obswrite': ['user/Observation.cruds'],
        }
        toks = {}
        for i, (u, sc) in enumerate(accounts.items()):
            s, _, b = g.req('POST', '/auth/register', {
                'username': u, 'password': g.PW, 'role': 'clinician',
                'scopes': sc}, adm, ip='127.0.3.%d' % (i + 10))
            assert s == 201, (u, s, b)
            toks[u], _ = g.login(u, g.PW, '127.0.4.%d' % (i + 10))

        def probe(case, user, method, path, body=None, allowed=(),
                  headers=None):
            s, _, b = g.req(method, path, body, toks[user], headers,
                            ip='127.0.5.1')
            t = types_in(b) if s == 200 else b[:160]
            bad = [x for x in (t or []) if isinstance(t, list) and
                   x not in allowed and x not in ('OperationOutcome', '-')]
            verdict = ('FAIL' if (s == 200 and bad) else
                       'PASS' if s != 200 or isinstance(t, list) else 'NOTE')
            log(case, accounts[user], s, t, verdict)
            return s, b

        O = ('Observation',)
        probe('chain to unreadable type', 'obsonly', 'GET',
              '/Observation?subject:Patient.family=' + g.OUT_MARK, allowed=O)
        s, _, b = g.req('GET', '/Observation?subject:Patient.family=' +
                     g.OUT_MARK, token=toks['obsonly'], ip='127.0.5.1')
        log('chain discloses an attribute of an unreadable type',
            accounts['obsonly'], s, 'total=%s' % json.loads(b).get('total')
            if s == 200 else b[:120],
            'FAIL' if s == 200 and json.loads(b).get('total') else 'PASS')
        probe('_include of unreadable type', 'obsonly', 'GET',
              '/Observation?_include=Observation:subject', allowed=O)
        probe('_include:iterate', 'obsonly', 'GET',
              '/Observation?_include:iterate=Observation:subject',
              allowed=O)
        probe('_revinclude of unreadable type', 'patonly', 'GET',
              '/Patient?_revinclude=Observation:subject',
              allowed=('Patient',))
        s, _, b = g.req('GET', '/Patient?_has:Observation:subject:code=8867-4',
                     token=toks['patonly'], ip='127.0.5.1')
        log('_has on unreadable type', accounts['patonly'], s,
            'total=%s' % json.loads(b).get('total') if s == 200
            else b[:120], 'NOTE')
        probe('$everything with Patient scope only', 'patonly', 'GET',
              '/Patient/pat2/$everything', allowed=('Patient',))
        probe('$everything Encounter with Observation scope', 'obsonly',
              'GET', '/Encounter/enc2/$everything', allowed=O)
        probe('compartment search via unreadable compartment', 'obsonly',
              'GET', '/Patient/pat2/Observation', allowed=O)
        probe('compartment search of unreadable type', 'patonly', 'GET',
              '/Patient/pat2/Observation', allowed=('Patient',))
        s, b = probe('$document with Composition scope only', 'componly',
                     'GET', '/Composition/comp2/$document',
                     allowed=('Composition',))
        if s == 200:
            j = json.loads(b)
            log('$document entry types', accounts['componly'], s,
                sorted({(e.get('resource') or {}).get('resourceType')
                        for e in j.get('entry', [])}),
                'FAIL' if any((e.get('resource') or {}).get('resourceType')
                              not in ('Composition',) for e in
                              j.get('entry', [])) else 'PASS')
        s, _, b = g.req('GET', '/Group/g1', token=toks['grouponly'],
                     ip='127.0.5.1')
        log('Group read lists members of an unreadable type',
            accounts['grouponly'], s, b[:200], 'NOTE')
        probe('Group export with Group scope only', 'grouponly', 'GET',
              '/Group/g1/$export', headers={'Prefer': 'respond-async'})
        probe('system search', 'obsonly', 'GET', '/?_type=Patient',
              allowed=O)
        probe('system search, no _type', 'obsonly', 'GET', '/?_count=50',
              allowed=O)
        probe('POST _search system', 'obsonly', 'POST', '/_search',
              '_type=Patient,Observation', allowed=O)
        probe('history system', 'obsonly', 'GET', '/_history?_count=100',
              allowed=O)
        probe('history type of unreadable', 'obsonly', 'GET',
              '/Patient/_history', allowed=O)
        probe('batch GET of unreadable type', 'obsonly', 'POST', '/', {
            'resourceType': 'Bundle', 'type': 'batch', 'entry': [
                {'request': {'method': 'GET', 'url': 'Patient/pat2'}},
                {'request': {'method': 'GET', 'url': 'Patient?_id=pat2'}}]},
              allowed=O)
        s, _, b = g.req('POST', '/', {
            'resourceType': 'Bundle', 'type': 'batch', 'entry': [
                {'request': {'method': 'GET', 'url': 'Patient/pat2'}},
                {'request': {'method': 'GET', 'url': 'Patient?_id=pat2'}}]},
            toks['obsonly'], ip='127.0.5.1')
        inner = [(e.get('response', {}).get('status'),
                  types_in(json.dumps(e.get('resource') or {})))
                 for e in json.loads(b).get('entry', [])] if s == 200 else b
        log('batch entries for unreadable type', accounts['obsonly'], s,
            inner, 'FAIL' if 'LEAKMARK' in b else 'PASS')
        s, _, b = g.req('POST', '/', {
            'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
                {'resource': {'resourceType': 'Observation', 'status':
                              'final', 'code': {'text': 'x'},
                              'subject': {'reference': 'Patient?family=' +
                                          g.OUT_MARK}},
                 'request': {'method': 'POST', 'url': 'Observation'}}]},
            toks['obswrite'], ip='127.0.5.1')
        log('conditional reference searches an unreadable type',
            accounts['obswrite'], s, b[:200], 'NOTE')
        s, _, b = g.req('POST', '/Observation', {
            'resourceType': 'Observation', 'status': 'final',
            'code': {'text': 'x'}}, toks['obswrite'], ip='127.0.5.1',
            headers={'If-None-Exist': 'subject:Patient.family=' +
                     g.OUT_MARK})
        log('If-None-Exist chain to unreadable type', accounts['obswrite'],
            s, b[:160], 'NOTE')
        for case, path in [
                ('$fhirpath on unreadable type', '/$fhirpath?expression=name'
                 '&resourceType=Patient&resourceId=pat2'),
                ('$meta of unreadable type', '/Patient/pat2/$meta'),
                ('vread of unreadable type', '/Patient/pat2/_history/1')]:
            s, _, b = g.req('GET', path, token=toks['obsonly'], ip='127.0.5.1')
            log(case, accounts['obsonly'], s, b[:160],
                'FAIL' if s == 200 else 'PASS')

        # 6.1.0.9 narrative active content
        for name, div in [
                ('script', '<div xmlns="http://www.w3.org/1999/xhtml">'
                 '<script>alert(1)</script></div>'),
                ('onclick', '<div xmlns="http://www.w3.org/1999/xhtml">'
                 '<p onclick="alert(1)">x</p></div>'),
                ('javascript href', '<div xmlns="http://www.w3.org/1999/'
                 'xhtml"><a href="javascript:alert(1)">x</a></div>'),
                ('iframe', '<div xmlns="http://www.w3.org/1999/xhtml">'
                 '<iframe src="http://x"></iframe></div>')]:
            s, _, b = g.req('POST', '/Patient', {
                'resourceType': 'Patient', 'text': {'status': 'generated',
                                                    'div': div}}, adm,
                ip=g.ROOT_IP)
            log('narrative %s' % name, 'admin', s, b[:140],
                'PASS' if s in (400, 422) else 'FAIL')
        # User content served as HTML
        html = base64.b64encode(b'<html><script>alert(document.domain)'
                                b'</script></html>').decode()
        s, _, b = g.req('PUT', '/Binary/bin1', {
            'resourceType': 'Binary', 'id': 'bin1', 'contentType':
            'text/html', 'data': html}, adm, ip=g.ROOT_IP)
        for acc in ['text/html', '*/*', 'application/fhir+json']:
            s, h, b = g.req('GET', '/Binary/bin1', token=adm, ip=g.ROOT_IP,
                            headers={'Accept': acc})
            ct = h.get('Content-Type') or h.get('content-type')
            log('Binary text/html read Accept=%s' % acc, 'admin', s,
                (ct, b[:80]), 'FAIL' if ct and 'text/html' in ct else 'PASS')
        # 6.1.0.3 error detail to unauthorised clients
        s, h, b = g.req('GET', '/Observation/obs1')
        log('401 headers', 'none', s, sorted(h.items()), 'NOTE')
        s, h, b = g.req('GET', '/Observation?date=garbage-date', token=adm,
                        ip=g.ROOT_IP)
        log('400 detail', 'admin', s, b[:300], 'NOTE')
        s, h, b = g.req('POST', '/auth/login', '{"username":', ip='127.0.5.2')
        log('login garbled detail', 'none', s, b[:300], 'NOTE')
    finally:
        g.stop(p)


if __name__ == '__main__':
    main()
