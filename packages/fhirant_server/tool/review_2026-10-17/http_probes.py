#!/usr/bin/env python3
"""R4B http.html (RESTful API) probes for the fifth fhirant review.

Each case quotes the sentence it tests (read in R4B http.html, downloaded
2026-10-17) and records what the server did. One row per case to
http_probes.tsv: case, rule, expected, observed, verdict (PASS / FAIL /
NOTE where the spec says MAY or the answer needs reading).

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/http_probes.py <server> <workdir>
"""
import json
import os
import shutil
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'http_probes.tsv')
IP = g.ROOT_IP
T = None


def log(case, rule, expected, observed, verdict):
    row = [str(case), str(rule), str(expected), str(observed).replace('\t', ' ')
           .replace('\n', ' ')[:300], verdict]
    with open(OUT, 'a') as f:
        f.write('\t'.join(row) + '\n')
        f.flush()
    print('\t'.join(row), flush=True)


def check(case, rule, expected, observed, ok):
    log(case, rule, expected, observed, 'PASS' if ok else 'FAIL')


def r(method, path, body=None, headers=None, token='default'):
    tok = T if token == 'default' else token
    return g.req(method, path, body, tok, headers, ip=IP)


def hget(h, name):
    for k, v in h.items():
        if k.lower() == name.lower():
            return v
    return None


def obs(i=None, value=None, **extra):
    o = {'resourceType': 'Observation', 'status': 'final',
         'code': {'coding': [{'system': 'http://loinc.org',
                              'code': '2823-3'}], 'text': 'Potassium'},
         'subject': {'reference': 'Patient/pat1'}}
    if i:
        o['id'] = i
    if value is not None:
        o['valueQuantity'] = {'value': value, 'unit': 'mmol/L',
                              'system': 'http://unitsofmeasure.org',
                              'code': 'mmol/L'}
    o.update(extra)
    return o


def main():
    global T
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\trule\texpected\tobserved\tverdict\n')
    d = os.path.join(work, 'http')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        T, _ = g.login('adm2', g.PW, IP)
        run()
    finally:
        g.stop(p)


def run():
    # --- read ---------------------------------------------------------
    s, h, b = r('GET', '/Observation/obs1')
    check('read ETag', 'Servers SHOULD return an ETag header with the '
          'versionId', 'W/"<vid>"', hget(h, 'ETag'),
          hget(h, 'ETag') == 'W/"%s"' % json.loads(b)['meta']['versionId'])
    check('read Last-Modified', 'and a Last-Modified header', 'present',
          hget(h, 'Last-Modified'), hget(h, 'Last-Modified') is not None)
    check('Date header', 'SHOULD return the default timezone in the HTTP '
          'Response headers using the "Date" header', 'present',
          hget(h, 'Date'), hget(h, 'Date') is not None)
    check('read id', 'The returned resource SHALL have an id element with a '
          'value that is the [id]', 'obs1', json.loads(b).get('id'),
          json.loads(b).get('id') == 'obs1')
    s, _, _ = r('GET', '/Observation/does-not-exist')
    check('read unknown', 'a GET for an unknown resource returns 404', 404, s,
          s == 404)
    s, h, b = r('GET', '/Observation/obs1?_summary=true')
    j = json.loads(b) if s == 200 else {}
    tags = [t.get('code') for t in j.get('meta', {}).get('tag', [])]
    check('read _summary=true SUBSETTED', 'Servers SHOULD define a '
          'Resource.meta.tag with the SUBSETTED', 'SUBSETTED tag, no '
          'valueQuantity-free check', (s, tags), s == 200 and
          'SUBSETTED' in tags)
    s, h, b = r('GET', '/Observation/obs1?_elements=status')
    j = json.loads(b) if s == 200 else {}
    tags = [t.get('code') for t in j.get('meta', {}).get('tag', [])]
    check('read _elements SUBSETTED', 'The same applies to the _elements '
          'parameter', 'only status (+mandatory) and SUBSETTED',
          (s, sorted(j.keys()), tags), s == 200 and 'code' not in j and
          'SUBSETTED' in tags)
    # conditional read
    s, h, b = r('GET', '/Observation/obs1')
    et = hget(h, 'ETag')
    s2, _, b2 = r('GET', '/Observation/obs1', headers={'If-None-Match': et})
    log('conditional read If-None-Match', 'they SHALL accept either a 304 '
        'Not Modified ... or full content', '304 or 200', (s2, len(b2)),
        'PASS' if s2 in (200, 304) else 'FAIL')
    # HEAD
    s1, h1, b1 = r('GET', '/Observation/obs1')
    s2, h2, b2 = r('HEAD', '/Observation/obs1')
    check('HEAD read', 'same response as a GET, but with no body', '200, '
          'empty body, same ETag', (s2, len(b2), hget(h2, 'ETag')),
          s2 == s1 and b2 == '' and hget(h2, 'ETag') == hget(h1, 'ETag'))
    s2, h2, b2 = r('HEAD', '/Observation?code=2823-3')
    check('HEAD search', 'Anywhere that a GET request can be used, a HEAD '
          'request is also allowed', '200 empty', (s2, len(b2)),
          s2 == 200 and b2 == '')
    s2, h2, b2 = r('HEAD', '/metadata')
    check('HEAD metadata', 'Anywhere that a GET request can be used',
          '200 empty', (s2, len(b2)), s2 == 200 and b2 == '')
    s2, h2, b2 = r('HEAD', '/Observation/obs1/_history')
    check('HEAD history', 'Anywhere that a GET request can be used',
          '200 empty', (s2, len(b2)), s2 == 200 and b2 == '')

    # --- content types -------------------------------------------------
    for acc, want in [('application/fhir+json', 200),
                      ('application/json', 200),
                      ('application/fhir+json; fhirVersion=4.3', 200),
                      ('application/fhir+xml', 406),
                      ('application/xml', 406),
                      ('text/html', None),
                      ('application/fhir+json; fhirVersion=4.0', None),
                      ('application/fhir+json; fhirVersion=5.0', None)]:
        s, h, b = r('GET', '/Observation/obs1', headers={'Accept': acc})
        ct = hget(h, 'Content-Type')
        if want is None:
            log('Accept %s' % acc, 'server-driven content negotiation',
                'read', (s, ct), 'NOTE')
        else:
            check('Accept %s' % acc, '406 Not Acceptable is the appropriate '
                  'response when the Accept header requests a format that '
                  'the server does not support', want, (s, ct), s == want)
    for fmt in ['json', 'application/json', 'application/fhir+json', 'xml',
                'html', 'text/html', 'ttl']:
        s, h, b = r('GET', '/Observation/obs1?_format=' +
                    urllib.parse.quote(fmt))
        log('_format=%s' % fmt, 'the codes json, application/json and '
            'application/fhir+json SHALL be interpreted to mean the JSON '
            'format', 'json 200; xml/ttl 406; html allowed',
            (s, hget(h, 'Content-Type')),
            'PASS' if (s == 200) == (fmt in ('json', 'application/json',
                                             'application/fhir+json'))
            or fmt in ('html', 'text/html') else 'FAIL')
    s, h, b = r('POST', '/Observation', '<Observation xmlns="http://hl7.org/'
                'fhir"/>', headers={'Content-Type': 'application/fhir+xml'})
    check('POST xml body', '415 Unsupported Media Type when the client posts '
          'a format that is not supported', 415, (s, b[:120]), s == 415)
    s, h, b = r('POST', '/Observation', json.dumps(obs()),
                headers={'Content-Type': 'text/plain'})
    log('POST text/plain body', '415 when the client posts a format that is '
        'not supported', 415, (s, b[:120]), 'PASS' if s == 415 else 'FAIL')
    s, h, b = r('POST', '/Observation', json.dumps(obs()), headers={
        'Content-Type': 'application/fhir+json; fhirVersion=4.3',
        'Accept': 'application/fhir+json; fhirVersion=4.0'})
    log('two fhirVersions', 'It is an error for a client to attempt to use '
        'two different versions in the same interaction', '4xx', (s, b[:120]),
        'PASS' if 400 <= s < 500 else 'FAIL')
    s, h, b = r('GET', '/Observation/obs1?_pretty=true')
    log('_pretty', 'servers MAY choose to support this parameter', '200',
        (s, b.count('\n')), 'NOTE')
    s, h, b = r('GET', '/Observation/obs1', headers={'Accept': 'text/json'})
    log('Accept text/json', 'If a client provides a generic mime type in the '
        'Accept header (application/xml, text/json, or application/json), '
        'the server SHOULD respond with the requested mime type', '200 json',
        (s, hget(h, 'Content-Type')), 'PASS' if s == 200 else 'FAIL')

    # --- create -------------------------------------------------------
    body = obs('client-id', 4.0)
    body['meta'] = {'versionId': '99', 'lastUpdated': '2001-01-01T00:00:00Z'}
    s, h, b = r('POST', '/Observation', body)
    loc = hget(h, 'Location') or ''
    j = json.loads(b) if b else {}
    check('create 201', 'The server returns a 201 Created', 201, s, s == 201)
    check('create ignores id', 'If an id is provided, the server SHALL '
          'ignore it', 'id != client-id', j.get('id'),
          j.get('id') not in (None, 'client-id'))
    check('create ignores meta', 'the server SHALL ignore the existing '
          'versionId and lastUpdated values', 'versionId 1, lastUpdated now',
          j.get('meta'), j.get('meta', {}).get('versionId') == '1' and
          not j.get('meta', {}).get('lastUpdated', '').startswith('2001'))
    check('create Location', 'Location: [base]/[type]/[id]/_history/[vid]',
          '/Observation/<id>/_history/1', loc,
          loc.endswith('/Observation/%s/_history/1' % j.get('id')))
    check('create ETag', 'Servers SHOULD return an ETag header', 'W/"1"',
          hget(h, 'ETag'), hget(h, 'ETag') == 'W/"1"')
    created = j.get('id')
    s, h, b = r('POST', '/Observation', '{"resourceType":"Observation"')
    check('create garbled', 'resource syntax or data is incorrect ... 400',
          400, s, s == 400)
    s, h, b = r('POST', '/Observation', {'resourceType': 'Patient'})
    log('create wrong type', 'The request body SHALL be a FHIR Resource '
        '(of the URL type)', '400', (s, b[:120]),
        'PASS' if s == 400 else 'FAIL')
    s, h, b = r('POST', '/Observation', {'resourceType': 'Observation',
                                         'status': 'not-a-status',
                                         'code': {'text': 'x'}})
    log('create invalid code', 'failed basic FHIR validation rules -> 400',
        '400 or 422', (s, b[:120]), 'PASS' if s in (400, 422) else 'FAIL')
    s, h, b = r('POST', '/Observation', {'resourceType': 'Observation',
                                         'code': {'text': 'x'}})
    log('create missing required status', 'failed basic FHIR validation '
        'rules -> 400', '400 or 422', (s, b[:120]),
        'PASS' if s in (400, 422) else 'FAIL')
    s, h, b = r('POST', '/Observation', {'resourceType': 'Observation',
                                         'status': 'final',
                                         'code': {'text': 'x'},
                                         'unknownElement': 1})
    log('create unknown element', 'failed basic FHIR validation rules',
        '400 or 422', (s, b[:120]), 'PASS' if s in (400, 422) else 'FAIL')
    # Prefer
    for pref, want in [('return=minimal', 'empty'),
                       ('return=representation', 'Observation'),
                       ('return=OperationOutcome', 'OperationOutcome')]:
        s, h, b = r('POST', '/Observation', obs(value=4.1),
                    headers={'Prefer': pref})
        got = 'empty' if b == '' else json.loads(b).get('resourceType')
        check('Prefer %s' % pref, 'Servers SHOULD honor this header', want,
              (s, got), got == want)
    # conditional create
    ident = {'system': 'urn:http-probe', 'value': 'cc1'}
    s1, _, _ = r('POST', '/Observation', obs(identifier=[ident]),
                 headers={'If-None-Exist': 'identifier=urn:http-probe|cc1'})
    s2, _, b2 = r('POST', '/Observation', obs(identifier=[ident]),
                  headers={'If-None-Exist': 'identifier=urn:http-probe|cc1'})
    check('conditional create', 'No matches: create; One Match: The server '
          'ignores the post and returns 200 OK', '201 then 200', (s1, s2),
          (s1, s2) == (201, 200))
    r('POST', '/Observation', obs(identifier=[ident]))
    s3, _, b3 = r('POST', '/Observation', obs(identifier=[ident]),
                  headers={'If-None-Exist': 'identifier=urn:http-probe|cc1'})
    check('conditional create multiple', 'Multiple matches: The server '
          'returns a 412', 412, (s3, b3[:100]), s3 == 412)

    # --- update -------------------------------------------------------
    s, h, b = r('PUT', '/Observation/obs1', obs(value=4.2))
    check('update no id', 'If no id element is provided ... the server SHALL '
          'respond with an HTTP 400', 400, s, s == 400)
    s, h, b = r('PUT', '/Observation/obs1', obs('other', 4.2))
    check('update id mismatch', 'or the id disagrees with the id in the URL '
          '... SHALL respond with an HTTP 400', 400, s, s == 400)
    body = obs('obs1', 4.3)
    body['meta'] = {'versionId': '77', 'lastUpdated': '2001-01-01T00:00:00Z'}
    s, h, b = r('PUT', '/Observation/obs1', body)
    j = json.loads(b) if b else {}
    check('update 200', 'SHALL return either a 200 OK ... if the resource '
          'was updated', 200, s, s == 200)
    check('update ignores meta', 'the server SHALL ignore the provided '
          'versionId and lastUpdated values', 'versionId != 77',
          j.get('meta'), j.get('meta', {}).get('versionId') not in
          (None, '77'))
    check('update ETag+Last-Modified', 'with a Last-Modified header, and an '
          'ETag header which contains the new versionId', 'both',
          (hget(h, 'ETag'), hget(h, 'Last-Modified')),
          hget(h, 'ETag') == 'W/"%s"' % j.get('meta', {}).get('versionId')
          and hget(h, 'Last-Modified') is not None)
    s, h, b = r('PUT', '/Observation/http-new', obs('http-new', 4.4))
    check('update as create', '201 Created status code if the resource was '
          'created ... SHOULD return a Location header', '201 + Location',
          (s, hget(h, 'Location')), s == 201 and hget(h, 'Location'))
    # If-Match
    s, h, b = r('GET', '/Observation/obs1')
    et = hget(h, 'ETag')
    s1, _, _ = r('PUT', '/Observation/obs1', obs('obs1', 4.5),
                 headers={'If-Match': 'W/"999"'})
    check('If-Match stale', 'If the version id given in the If-Match header '
          'does not match, the server returns a 412', 412, s1, s1 == 412)
    s2, _, _ = r('PUT', '/Observation/obs1', obs('obs1', 4.5),
                 headers={'If-Match': et})
    check('If-Match current', 'version aware update', 200, s2, s2 == 200)
    s3, _, b3 = r('PUT', '/Observation/obs1', obs('obs1', 4.5),
                  headers={'If-Match': 'garbage'})
    log('If-Match garbage', 'If-Match: W/"23"', '4xx', (s3, b3[:100]),
        'PASS' if 400 <= s3 < 500 else 'FAIL')
    # conditional update
    cu = {'system': 'urn:http-probe', 'value': 'cu1'}
    s1, _, b1 = r('PUT', '/Observation?identifier=urn:http-probe|cu1',
                  obs(identifier=[cu], value=1))
    check('cond update no match no id', 'No matches, no id provided: The '
          'server creates the resource', 201, s1, s1 == 201)
    cid = json.loads(b1).get('id') if b1 else None
    s2, _, b2 = r('PUT', '/Observation?identifier=urn:http-probe|cu1',
                  obs(identifier=[cu], value=2))
    check('cond update one match', 'One Match, no resource id provided: '
          'update', '200 same id', (s2, json.loads(b2).get('id') if b2
                                     else None),
          s2 == 200 and b2 and json.loads(b2).get('id') == cid)
    s3, _, b3 = r('PUT', '/Observation?identifier=urn:http-probe|cu1',
                  obs('not-the-match', identifier=[cu], value=3))
    check('cond update id mismatch', 'One Match, resource id provided but '
          'does not match resource found: 400', 400, (s3, b3[:120]),
          s3 == 400)
    s4, _, b4 = r('PUT', '/Observation?identifier=urn:http-probe|cu-none',
                  obs('cu-given', identifier=[{'system': 'urn:http-probe',
                                               'value': 'cu-none'}]))
    check('cond update no match id given', 'No matches, id provided: Update '
          'as Create', '201 with id cu-given', (s4, json.loads(b4).get('id')
                                               if b4 else None),
          s4 == 201 and b4 and json.loads(b4).get('id') == 'cu-given')
    r('POST', '/Observation', obs(identifier=[cu]))
    s5, _, b5 = r('PUT', '/Observation?identifier=urn:http-probe|cu1',
                  obs(identifier=[cu]))
    check('cond update multiple', 'Multiple matches: 412', 412, s5, s5 == 412)

    # --- patch --------------------------------------------------------
    s, h, b = r('GET', '/Observation/obs1')
    et = hget(h, 'ETag')
    jp = '[{"op":"replace","path":"/status","value":"amended"}]'
    s1, h1, b1 = r('PATCH', '/Observation/obs1', jp, headers={
        'Content-Type': 'application/json-patch+json', 'If-Match': 'W/"999"'})
    check('PATCH If-Match stale', 'servers SHALL support conditional PATCH',
          412, s1, s1 == 412)
    s2, h2, b2 = r('PATCH', '/Observation/obs1', jp, headers={
        'Content-Type': 'application/json-patch+json', 'If-Match': et})
    check('PATCH If-Match current', 'conditional PATCH', 200,
          (s2, hget(h2, 'ETag')), s2 == 200)
    s3, h3, b3 = r('PATCH', '/Observation/obs1', jp, headers={
        'Content-Type': 'application/json-patch+json',
        'Prefer': 'return=minimal'})
    check('PATCH Prefer minimal', 'as does the Prefer Header', 'empty',
          (s3, len(b3)), s3 == 200 and b3 == '')
    fp = {'resourceType': 'Parameters', 'parameter': [{
        'name': 'operation', 'part': [
            {'name': 'type', 'valueCode': 'replace'},
            {'name': 'path', 'valueString': 'Observation.status'},
            {'name': 'value', 'valueCode': 'final'}]}]}
    s4, _, b4 = r('PATCH', '/Observation/obs1', fp)
    log('FHIRPath Patch', 'The body of a PATCH operation SHALL be either ... '
        'a FHIRPath Patch parameters resource', 'supported or 4xx',
        (s4, b4[:120]), 'NOTE')
    s5, _, b5 = r('PATCH', '/Observation?identifier=urn:http-probe|none', jp,
                  headers={'Content-Type': 'application/json-patch+json'})
    log('conditional PATCH by search, no match', 'No matches: The server '
        'returns a 404 Not Found (SHOULD, servers that support conditional '
        'update)', 404, (s5, b5[:120]), 'PASS' if s5 == 404 else 'FAIL')
    s6, _, b6 = r('PATCH', '/Observation?identifier=urn:http-probe|cu1', jp,
                  headers={'Content-Type': 'application/json-patch+json'})
    log('conditional PATCH by search, multiple', 'Multiple matches: 412',
        412, (s6, b6[:120]), 'PASS' if s6 == 412 else 'FAIL')
    # Narrative safety: a lab value whose human-readable narrative the patch
    # makes false.
    nar = obs('nar1', 3.0)
    nar['text'] = {'status': 'additional', 'div': '<div xmlns="http://www.w3'
                   '.org/1999/xhtml">Potassium 3.0 mmol/L (LOW)</div>'}
    r('PUT', '/Observation/nar1', nar)
    s7, _, b7 = r('PATCH', '/Observation/nar1', '[{"op":"replace","path":'
                  '"/valueQuantity/value","value":6.5}]',
                  headers={'Content-Type': 'application/json-patch+json'})
    s8, _, b8 = r('GET', '/Observation/nar1')
    j8 = json.loads(b8)
    check('PATCH narrative safety', 'The server SHALL ensure that the '
          'narrative in a resource is not clinically unsafe after the PATCH '
          'operation is performed', 'reject, regenerate or drop the stale '
          'narrative', (s7, j8.get('valueQuantity', {}).get('value'),
                        j8.get('text', {}).get('div')),
          not (j8.get('valueQuantity', {}).get('value') == 6.5 and
               '3.0' in j8.get('text', {}).get('div', '')))

    # --- delete -------------------------------------------------------
    r('PUT', '/Observation/del1', obs('del1', 4.0))
    s1, _, b1 = r('DELETE', '/Observation/del1')
    check('delete', '200 OK if the response contains a payload, or a 204 No '
          'Content', '200/202/204', s1, s1 in (200, 202, 204))
    s2, h2, _ = r('GET', '/Observation/del1')
    check('read deleted', 'subsequent non-version specific reads of a '
          'resource return a 410', 410, s2, s2 == 410)
    s3, _, b3 = r('GET', '/Observation?_id=del1')
    check('search deleted', 'the resource is no longer found through search',
          'total 0', json.loads(b3).get('total'),
          json.loads(b3).get('total') == 0)
    s4, _, _ = r('DELETE', '/Observation/del1')
    check('delete again', 'Performing this interaction on a resource that is '
          'already deleted has no effect, ... 200 or 204', '200/204', s4,
          s4 in (200, 204))
    s5, _, _ = r('DELETE', '/Observation/never-existed')
    check('delete absent', 'or if the resource does not exist at all, the '
          'server should return either a 200 OK ... or a 204', '200/202/204',
          s5, s5 in (200, 202, 204))
    s6, _, b6 = r('GET', '/Observation/del1/_history')
    ents = json.loads(b6).get('entry', []) if s6 == 200 else []
    check('delete keeps history', 'the delete interaction does not remove a '
          "resource's version history", '>=2 entries, newest DELETE',
          (s6, [e.get('request', {}).get('method') for e in ents]),
          len(ents) >= 2 and ents[0].get('request', {}).get('method') ==
          'DELETE')
    s7, _, b7 = r('GET', '/Observation/del1/_history/2')
    log('vread deleted version', 'If the version referred to is actually '
        'one where the resource was deleted, the server should return a 410',
        410, (s7, b7[:100]), 'PASS' if s7 == 410 else 'FAIL')
    s8, _, b8 = r('PUT', '/Observation/del1', obs('del1', 5.0))
    check('bring back to life', 'Resources that have been deleted may be '
          '"brought back to life" by a subsequent update ... 201 Created if '
          '... brought back to life/re-created', 201, s8, s8 == 201)
    r('PUT', '/Observation/delb', obs('delb'))
    s9, _, b9 = r('DELETE', '/Observation/delb', '{"x":1}')
    log('delete with body', 'The request body SHALL be empty', 'note',
        (s9, b9[:100]), 'NOTE')
    # conditional delete
    for i in range(2):
        r('POST', '/Observation', obs(identifier=[
            {'system': 'urn:http-probe', 'value': 'cd'}]))
    s10, _, b10 = r('DELETE', '/Observation?identifier=urn:http-probe|cd')
    s11, _, b11 = r('GET', '/Observation?identifier=urn:http-probe|cd')
    _, _, cap = r('GET', '/metadata')
    cdel = [x.get('conditionalDelete') for x in
            json.loads(cap)['rest'][0]['resource']
            if x['type'] == 'Observation']
    check('conditional delete multiple', 'delete all the matching resources, '
          'or ... 412; A server indicates whether it can delete multiple '
          'resources in its Capability Statement', 'matches the capability '
          'statement', (s10, json.loads(b11).get('total'), cdel),
          (cdel == ['multiple'] and json.loads(b11).get('total') == 0) or
          (cdel == ['single'] and s10 == 412))

    # --- search -------------------------------------------------------
    s1, _, b1 = r('GET', '/Observation?code=2823-3&_count=2')
    s2, _, b2 = r('POST', '/Observation/_search', 'code=2823-3&_count=2')
    j1, j2 = json.loads(b1), json.loads(b2)
    check('POST _search same', 'servers that support search SHALL also '
          'support a POST based search ... exactly the same semantics',
          'same total', (j1.get('total'), j2.get('total')),
          s2 == 200 and j1.get('total') == j2.get('total'))
    s3, _, b3 = r('POST', '/Observation/_search?code=2823-3', '_count=2')
    check('POST _search URL+body', 'parameters may appear in both the URL '
          'and the body', 'same total', json.loads(b3).get('total'),
          json.loads(b3).get('total') == j1.get('total'))
    check('searchset', 'the return content SHALL be a Bundle with type = '
          'searchset', 'searchset', j1.get('type'),
          j1.get('type') == 'searchset')
    self_link = [x['url'] for x in j1.get('link', [])
                 if x['relation'] == 'self']
    check('self link', 'All searches SHALL return this value', 'present',
          self_link, bool(self_link))
    nxt = [x['url'] for x in j1.get('link', []) if x['relation'] == 'next']
    if nxt:
        u = urllib.parse.urlsplit(nxt[0])
        s4, _, b4 = r('GET', u.path + ('?' + u.query if u.query else ''))
        j4 = json.loads(b4)
        ids1 = {e['resource']['id'] for e in j1.get('entry', [])}
        ids4 = {e['resource']['id'] for e in j4.get('entry', [])}
        check('next page', 'The client must use the server supplied links',
              'page 2, disjoint', (s4, len(ids4), ids1 & ids4),
              s4 == 200 and ids4 and not ids1 & ids4)
        s5, _, b5 = r('POST', u.path.rstrip('/') + '/_search'
                      if not u.path.endswith('_search') else u.path, u.query)
        log('next page via POST', 'servers SHOULD allow for a client to '
            'convert the follow up requests to be made via a POST', '200',
            (s5, b5[:100]), 'PASS' if s5 == 200 else 'FAIL')
    s6, _, b6 = r('GET', '/Observation?not-a-param=1')
    log('unknown search param', 'see search.html handling', 'read',
        (s6, b6[:200]), 'NOTE')
    s7, _, b7 = r('GET', '/Patient/pat1/*')
    log('compartment *', 'In the first URL the character "*" appears in the '
        "URL as a literal to mean 'all types'", '200 searchset',
        (s7, b7[:120]), 'PASS' if s7 == 200 else 'FAIL')
    s8, _, b8 = r('GET', '/?_type=Condition,Observation&code=2823-3')
    log('_type two types, shared param', 'the only parameters that can be '
        'used are those defined for both', '200', (s8, b8[:120]),
        'PASS' if s8 == 200 else 'FAIL')
    s9, _, b9 = r('GET', '/?_type=Patient,Observation&code=2823-3')
    check('_type param not on both', 'If a search lists types not listed in '
          'SearchParameter.base for any of the parameters, this is an error, '
          'and a server SHOULD return a 400', 400, (s9, b9[:120]), s9 == 400)
    s10, _, b10 = r('GET', '/?code=2823-3')
    log('system search non-base param', 'the only search parameters that be '
        'can be used in global search like this are the base parameters',
        '400', (s10, b10[:120]), 'PASS' if s10 == 400 else 'FAIL')

    # --- capabilities -------------------------------------------------
    s, h, b = r('GET', '/metadata', token=None)
    check('metadata ETag', 'An ETag header SHOULD be returned with the '
          'Response', 'present', hget(h, 'ETag'), hget(h, 'ETag'))
    j = json.loads(b)
    check('metadata fhirVersion', 'CapabilityStatement.fhirVersion',
          '4.3.0', j.get('fhirVersion'), j.get('fhirVersion') == '4.3.0')
    log('metadata conditionalDelete/update/versioning', 'Systems declare '
        'their support for versioning in their Capability Statements',
        'read', [(x['type'], x.get('versioning'), x.get('updateCreate'),
                  x.get('conditionalDelete'), x.get('conditionalUpdate'),
                  x.get('conditionalCreate'), x.get('readHistory'))
                 for x in j['rest'][0]['resource']
                 if x['type'] == 'Observation'], 'NOTE')
    s, h, b = r('GET', '/metadata?mode=terminology', token=None)
    log('metadata mode=terminology', 'A TerminologyCapabilities resource '
        '(Servers MAY ignore the mode parameter)', 'TerminologyCapabilities '
        'or CapabilityStatement', json.loads(b).get('resourceType'), 'NOTE')

    # --- batch / transaction ------------------------------------------
    tx = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'fullUrl': 'urn:uuid:11111111-1111-1111-1111-111111111111',
         'resource': {'resourceType': 'Patient', 'name': [{'family': 'Tx'}],
                      'link': [{'type': 'seealso', 'other': {
                          'reference': 'urn:uuid:22222222-2222-2222-2222-'
                                       '222222222222'}}]},
         'request': {'method': 'POST', 'url': 'Patient'}},
        {'fullUrl': 'urn:uuid:22222222-2222-2222-2222-222222222222',
         'resource': {'resourceType': 'Patient', 'name': [{'family': 'Tx2'}],
                      'link': [{'type': 'seealso', 'other': {
                          'reference': 'urn:uuid:11111111-1111-1111-1111-'
                                       '111111111111'}}]},
         'request': {'method': 'POST', 'url': 'Patient'}},
        {'fullUrl': 'urn:uuid:33333333-3333-3333-3333-333333333333',
         'resource': {'resourceType': 'Observation', 'status': 'final',
                      'code': {'text': 'tx'},
                      'subject': {'reference': 'urn:uuid:11111111-1111-1111-'
                                               '1111-111111111111'},
                      'derivedFrom': [{'reference': 'Observation/obs1/'
                                                    '_history/1'}],
                      'text': {'status': 'generated', 'div': '<div xmlns="h'
                               'ttp://www.w3.org/1999/xhtml"><a href="urn:uu'
                               'id:11111111-1111-1111-1111-111111111111">p</'
                               'a></div>'},
                      'extension': [{'url': 'urn:x', 'valueUri':
                                     'urn:uuid:11111111-1111-1111-1111-'
                                     '111111111111'}]},
         'request': {'method': 'POST', 'url': 'Observation'}}]}
    s, h, b = r('POST', '/', tx)
    j = json.loads(b)
    check('transaction 200', 'servers SHALL either accept all actions and '
          'return a 200 OK, along with a response bundle', '200 '
          'transaction-response', (s, j.get('type')),
          s == 200 and j.get('type') == 'transaction-response')
    locs = [e.get('response', {}).get('location') for e in j.get('entry', [])]
    check('transaction response entries', 'one entry for each entry in the '
          'request, in the same order ... SHALL contain a response element',
          '3 entries with location', locs, len(locs) == 3 and all(locs))
    if len(locs) == 3 and all(locs):
        p1 = locs[0].split('/_history')[0].split('Patient/')[-1]
        o = locs[2].split('/_history')[0].split('Observation/')[-1]
        _, _, ob = r('GET', '/Observation/' + o)
        ob = json.loads(ob)
        _, _, pb = r('GET', '/Patient/' + locs[1].split('/_history')[0]
                     .split('Patient/')[-1])
        pb = json.loads(pb)
        check('tx reference rewritten', 'it SHALL also update any references '
              'to that resource', 'Patient/' + p1,
              ob.get('subject', {}).get('reference'),
              ob.get('subject', {}).get('reference') == 'Patient/' + p1)
        check('tx circular reference', 'including circular references',
              'Patient/' + p1, pb.get('link', [{}])[0].get('other', {})
              .get('reference'), pb.get('link', [{}])[0].get('other', {})
              .get('reference') == 'Patient/' + p1)
        check('tx version-specific ref kept', 'Version-specific references '
              'should remain as version-specific references',
              'Observation/obs1/_history/1',
              ob.get('derivedFrom', [{}])[0].get('reference'),
              ob.get('derivedFrom', [{}])[0].get('reference') ==
              'Observation/obs1/_history/1')
        check('tx uri element rewritten', 'Servers SHALL replace all matching '
              'links in the bundle, whether they are found in ... elements of '
              'type uri', 'Patient/' + p1, ob.get('extension', [{}])[0]
              .get('valueUri'), ob.get('extension', [{}])[0].get('valueUri')
              in ('Patient/' + p1, locs[0].split('/_history')[0]))
        check('tx narrative href rewritten', 'and <a href="" ... in the '
              'narrative', 'no urn:uuid in div', ob.get('text', {})
              .get('div'), 'urn:uuid' not in ob.get('text', {}).get('div',
                                                                     ''))
    # atomicity
    before = json.loads(r('GET', '/Patient?family=Atomic')[2]).get('total')
    bad = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'resource': {'resourceType': 'Patient', 'name': [{'family':
                                                            'Atomic'}]},
         'request': {'method': 'POST', 'url': 'Patient'}},
        {'resource': {'resourceType': 'Observation', 'status': 'bogus',
                      'code': {'text': 'x'}},
         'request': {'method': 'POST', 'url': 'Observation'}}]}
    s, _, b = r('POST', '/', bad)
    after = json.loads(r('GET', '/Patient?family=Atomic')[2]).get('total')
    check('transaction atomic', 'or reject all resources and return an HTTP '
          '400 or 500 type response', '4xx/5xx, nothing stored',
          (s, before, after, json.loads(b).get('resourceType')),
          s >= 400 and before == after)
    check('failed transaction OO', 'For a failed transaction, the server '
          'returns a single OperationOutcome', 'OperationOutcome',
          json.loads(b).get('resourceType'),
          json.loads(b).get('resourceType') == 'OperationOutcome')
    # overlapping identities
    ov = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'resource': obs('ov1', 1), 'request': {'method': 'PUT',
                                                'url': 'Observation/ov1'}},
        {'resource': obs('ov1', 2), 'request': {'method': 'PUT',
                                                'url': 'Observation/ov1'}}]}
    s, _, b = r('POST', '/', ov)
    check('tx overlapping identities', 'If any resource identities ... '
          'overlap in steps 1-3, then the transaction SHALL fail', '4xx',
          (s, b[:120]), s >= 400)
    ov2 = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'request': {'method': 'DELETE', 'url': 'Observation/obs1'}},
        {'resource': obs('obs1', 2), 'request': {'method': 'PUT',
                                                 'url': 'Observation/obs1'}}]}
    s, _, b = r('POST', '/', ov2)
    check('tx overlapping DELETE+PUT', 'If any resource identities ... '
          'overlap in steps 1-3, then the transaction SHALL fail', '4xx',
          (s, b[:120]), s >= 400)
    # conditional references
    cr = lambda ref: {'resourceType': 'Bundle', 'type': 'transaction',  # noqa
                      'entry': [{'resource': dict(obs(), subject={
                          'reference': ref}), 'request': {
                              'method': 'POST', 'url': 'Observation'}}]}
    s1, _, b1 = r('POST', '/', cr('Patient?_id=pat1'))
    ok1 = False
    if s1 == 200:
        loc = json.loads(b1)['entry'][0]['response']['location']
        o = json.loads(r('GET', '/' + loc.split('/_history')[0]
                         .split('/', 3)[-1] if loc.startswith('http')
                         else '/' + loc.split('/_history')[0])[2])
        ok1 = o.get('subject', {}).get('reference') == 'Patient/pat1'
    check('conditional reference single', 'if there is a single match, the '
          'server replaces the search URI', 'Patient/pat1', (s1, b1[:150]),
          ok1)
    s2, _, b2 = r('POST', '/', cr('Patient?_id=nobody'))
    check('conditional reference none', 'if there are no matches ... the '
          'transaction fails', '4xx', (s2, b2[:120]), s2 >= 400)
    s3, _, b3 = r('POST', '/', cr('Patient?_id=pat1,pat2'))
    check('conditional reference multiple', 'or multiple matches, the '
          'transaction fails', '4xx', (s3, b3[:120]), s3 >= 400)
    s4, _, b4 = r('POST', '/', dict(cr('Patient?_id=pat1'), type='batch'))
    log('conditional reference in batch', 'in a transaction (and only in a '
        'transaction), references to resources may be replaced by a search '
        'URI', 'not resolved in a batch', (s4, b4[:200]), 'NOTE')
    # batch
    bt = {'resourceType': 'Bundle', 'type': 'batch', 'entry': [
        {'request': {'method': 'GET', 'url': 'Observation/obs1'}},
        {'request': {'method': 'GET', 'url': 'Observation/nope'}},
        {'resource': {'resourceType': 'Observation', 'status': 'bogus',
                      'code': {'text': 'x'}},
         'request': {'method': 'POST', 'url': 'Observation'}}]}
    s, _, b = r('POST', '/', bt)
    j = json.loads(b)
    check('batch 200 with failing entries', 'the HTTP response code is 200 '
          'Ok if the batch was processed correctly, regardless of the success '
          'of the operations', '200, statuses 200/404/4xx',
          (s, [e.get('response', {}).get('status') for e in
               j.get('entry', [])]),
          s == 200 and len(j.get('entry', [])) == 3)
    s, _, b = r('POST', '/', {'resourceType': 'Bundle', 'type':
                              'transaction'})
    check('empty transaction', 'It is not an error if the submitted bundle '
          'has no resources in it', 200, (s, b[:100]), s == 200)
    hist = {'resourceType': 'Bundle', 'type': 'history', 'entry': [
        {'resource': obs('hist1', 1), 'request': {'method': 'PUT',
                                                  'url': 'Observation/hist1'},
         'response': {'status': '201'}}]}
    s, _, b = r('POST', '/', hist)
    log('history bundle', 'servers SHOULD accept a history Bundle', '200',
        (s, b[:150]), 'PASS' if s == 200 else 'FAIL')
    col = {'resourceType': 'Bundle', 'type': 'collection', 'entry': [
        {'resource': obs('coll1', 1)}]}
    s, _, b = r('POST', '/', col)
    log('collection bundle', 'A server may choose to accept bundle types '
        'other than batch or transaction', 'read', (s, b[:150]), 'NOTE')
    s, _, b = r('POST', '/', {'resourceType': 'Bundle', 'type': 'transaction',
                              'entry': [{'resource': obs()}]})
    check('entry without request', 'Each entry SHALL carry request details',
          '4xx', (s, b[:120]), s >= 400)
    s, _, b = r('POST', '/', {'resourceType': 'Bundle', 'type': 'transaction',
                              'entry': [{'request': {'method': 'POST',
                                                     'url': 'Observation'}}]})
    check('POST entry without resource', 'If the HTTP command is a PUT or '
          'POST, then the entry SHALL contain a resource', '4xx',
          (s, b[:120]), s >= 400)

    # --- history ------------------------------------------------------
    r('PUT', '/Observation/h1', obs('h1', 1))
    time.sleep(1.1)
    mid = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    time.sleep(1.1)
    r('PUT', '/Observation/h1', obs('h1', 2))
    r('DELETE', '/Observation/h1')
    s, _, b = r('GET', '/Observation/h1/_history')
    j = json.loads(b)
    ents = j.get('entry', [])
    meth = [e.get('request', {}).get('method') for e in ents]
    check('history order', 'sorted with oldest versions last, and including '
          'deleted resources', '[DELETE, PUT, PUT|POST]', meth,
          len(meth) == 3 and meth[0] == 'DELETE')
    check('history PUT/POST has resource', 'If the entry.request.method is a '
          'PUT or a POST, the entry SHALL contain a resource', 'all',
          [bool(e.get('resource')) for e in ents],
          all(e.get('resource') for e in ents if
              e.get('request', {}).get('method') in ('PUT', 'POST')))
    check('history lastModified', 'The server SHOULD populate at least '
          'response.lastModified', 'all', [e.get('response', {})
                                           .get('lastModified') for e in ents],
          all(e.get('response', {}).get('lastModified') for e in ents))
    check('history type', 'a Bundle with type set to history', 'history',
          j.get('type'), j.get('type') == 'history')
    s, _, b = r('GET', '/Observation/h1/_history?_since=' + mid)
    n = len(json.loads(b).get('entry', [])) if s == 200 else None
    check('history _since', 'Only include resource versions that were '
          'created at or after the given instant', '2', (s, n), n == 2)
    s, _, b = r('GET', '/Observation/h1/_history?_at=' + mid)
    log('history _at', 'Only include resource versions that were current at '
        'some point during the time period', 'version 1 only', (s, b[:200]),
        'NOTE')
    s, _, b = r('GET', '/Observation/h1/_history?_count=1&_count=2')
    check('history repeated param', 'Each of these parameters SHALL NOT '
          'appear more than once', '400', (s, b[:120]), s == 400)
    s, _, b = r('GET', '/_history?_count=2')
    j = json.loads(b)
    nxt = [x['url'] for x in j.get('link', []) if x['relation'] == 'next']
    check('history paging _count', 'respect the specified _count across '
          'pages', '2 entries + next', (len(j.get('entry', [])), bool(nxt)),
          len(j.get('entry', [])) == 2 and nxt)
    if nxt:
        u = urllib.parse.urlsplit(nxt[0])
        s2, _, b2 = r('GET', u.path + '?' + u.query)
        check('history next page _count', 'respect the specified _count '
              'across pages', 2, (s2, len(json.loads(b2).get('entry', []))),
              len(json.loads(b2).get('entry', [])) == 2)
    s, _, b = r('GET', '/Observation/nope-nope/_history')
    log('history of unknown', 'If a request is made for a history that is '
        'not available ... 404', '404', (s, b[:120]),
        'PASS' if s == 404 else 'FAIL')

    # --- custom headers -----------------------------------------------
    s, h, b = r('GET', '/Observation/obs1', headers={'X-Request-Id': 'abc'})
    log('X-Request-Id', 'The server can either use that id or assign its own, '
        'which it returns as the X-Request-Id header', 'echo or own + '
        'X-Correlation-Id', (hget(h, 'X-Request-Id'),
                             hget(h, 'X-Correlation-Id')),
        'PASS' if hget(h, 'X-Request-Id') else 'FAIL')
    # operations via form post
    s, _, b = r('POST', '/ValueSet/$expand', 'url=' + urllib.parse.quote(
        'http://hl7.org/fhir/ValueSet/administrative-gender'))
    log('operation form POST', '(operation) POST application/x-www-form-'
        'urlencoded form data', '200', (s, b[:120]),
        'PASS' if s == 200 else 'FAIL')
    s, _, b = r('GET', '/Observation/obs1/$meta')
    check('$meta', 'Resource Operations', '200 Parameters',
          (s, json.loads(b).get('resourceType')), s == 200)


if __name__ == '__main__':
    main()
