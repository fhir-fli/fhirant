#!/usr/bin/env python3
"""Second look at the http_probes FAIL rows whose probe could have been
wrong. Writes http_followups.tsv.
Run: python3 -I tool/review_2026-10-17/http_followups.py <server> <workdir>"""
import json, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g
OUT = os.path.join(g.HERE, 'http_followups.tsv')
def log(*c):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400] for x in c)
    with open(OUT, 'a') as f:
        f.write(line + '\n'); f.flush()
    print(line, flush=True)
g.BIN, work = sys.argv[1], sys.argv[2]
open(OUT, 'w').write('case\tobserved\n')
d = os.path.join(work, 'httpf'); shutil.rmtree(d, ignore_errors=True)
shutil.copytree(os.path.join(work, 'seed'), d)
p = g.start(os.path.join(d, 'db'), d)
try:
    T, _ = g.login('adm2', g.PW, g.ROOT_IP)
    r = lambda m, path, b=None, h=None: g.req(m, path, b, T, h, ip=g.ROOT_IP)
    # Invalid status code: what is stored and read back?
    s, _, b = r('POST', '/Observation', {'resourceType': 'Observation', 'status': 'not-a-status', 'code': {'text': 'x'}})
    i = json.loads(b)['id']
    s2, _, b2 = r('GET', '/Observation/' + i)
    log('invalid status: create, read back status', s, json.loads(b2).get('status'))
    s3, _, b3 = r('GET', '/Observation?status=not-a-status&_id=' + i)
    log('invalid status: searchable', s3, json.loads(b3).get('total'))
    s4, _, b4 = r('POST', '/Observation/$validate', json.loads(b2))
    log('invalid status: $validate of the stored copy', s4, b4[:300])
    # Unknown element: kept or dropped?
    s, _, b = r('POST', '/Observation', {'resourceType': 'Observation', 'status': 'final', 'code': {'text': 'x'}, 'unknownElement': 1, 'valueQuantity': {'value': 1, 'unknownInner': 'y'}})
    i = json.loads(b)['id']
    _, _, b2 = r('GET', '/Observation/' + i)
    log('unknown element: create status, read back keys', s, sorted(json.loads(b2).keys()), json.loads(b2).get('valueQuantity'))
    # Wrong JSON type for a primitive.
    s, _, b = r('POST', '/Observation', {'resourceType': 'Observation', 'status': 'final', 'code': {'text': 'x'}, 'valueQuantity': {'value': 'six point five'}})
    log('string where decimal is required', s, b[:200])
    # Transaction atomicity with an entry that really fails (PUT id mismatch).
    before = json.loads(r('GET', '/Patient?family=Atomic2')[2]).get('total')
    bad = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'resource': {'resourceType': 'Patient', 'name': [{'family': 'Atomic2'}]}, 'request': {'method': 'POST', 'url': 'Patient'}},
        {'resource': {'resourceType': 'Observation', 'id': 'aaa', 'status': 'final', 'code': {'text': 'x'}}, 'request': {'method': 'PUT', 'url': 'Observation/bbb'}}]}
    s, _, b = r('POST', '/', bad)
    after = json.loads(r('GET', '/Patient?family=Atomic2')[2]).get('total')
    log('tx atomic (PUT id mismatch)', s, json.loads(b).get('resourceType'), 'before', before, 'after', after)
    bad2 = dict(bad, entry=[bad['entry'][0], {'request': {'method': 'DELETE', 'url': 'NotAType/1'}}])
    s, _, b = r('POST', '/', bad2)
    after2 = json.loads(r('GET', '/Patient?family=Atomic2')[2]).get('total')
    log('tx atomic (unknown type)', s, b[:150], 'after', after2)
    # Conditional reference: what is stored?
    for ref in ['Patient?_id=pat1', 'Patient?identifier=urn:none|x']:
        tx = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
            {'resource': {'resourceType': 'Observation', 'status': 'final', 'code': {'text': 'condref'}, 'subject': {'reference': ref}}, 'request': {'method': 'POST', 'url': 'Observation'}}]}
        s, _, b = r('POST', '/', tx)
        loc = json.loads(b)['entry'][0]['response']['location'] if s == 200 else ''
        oid = loc.split('Observation/')[1].split('/')[0] if 'Observation/' in loc else ''
        _, _, ob = r('GET', '/Observation/' + oid)
        log('conditional reference %s' % ref, s, 'stored subject:', json.loads(ob).get('subject'))
    _, _, ev = r('GET', '/Patient/pat1/$everything')
    log('pat1 $everything holds a condref Observation', 'condref' in ev)
    # Overlapping identities: what did the store keep?
    ov = {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
        {'resource': {'resourceType': 'Observation', 'id': 'ov9', 'status': 'final', 'code': {'text': 'first'}}, 'request': {'method': 'PUT', 'url': 'Observation/ov9'}},
        {'resource': {'resourceType': 'Observation', 'id': 'ov9', 'status': 'final', 'code': {'text': 'second'}}, 'request': {'method': 'PUT', 'url': 'Observation/ov9'}}]}
    s, _, b = r('POST', '/', ov)
    _, _, ob = r('GET', '/Observation/ov9')
    log('overlap: stored', s, json.loads(ob).get('code'), json.loads(ob)['meta']['versionId'])
    # If-Match garbage against a stale version.
    r('PUT', '/Observation/im1', {'resourceType': 'Observation', 'id': 'im1', 'status': 'final', 'code': {'text': 'v1'}})
    for im in ['garbage', '"1"', 'W/1', '*', 'W/"1", W/"2"']:
        r('PUT', '/Observation/im1', {'resourceType': 'Observation', 'id': 'im1', 'status': 'final', 'code': {'text': 'bump'}})
        s, _, b = r('PUT', '/Observation/im1', {'resourceType': 'Observation', 'id': 'im1', 'status': 'final', 'code': {'text': 'im'}}, {'If-Match': im})
        log('If-Match %s (current version >1)' % im, s)
finally:
    g.stop(p)
