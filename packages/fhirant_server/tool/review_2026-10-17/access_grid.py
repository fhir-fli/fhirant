#!/usr/bin/env python3
"""Access grid for the fifth fhirant review (2026-10-17).

Every registered route, plus paths outside the route list, called over real
HTTP against the compiled CLI server, once per identity. Each identity gets a
fresh copy of one seeded store, so one identity's writes never change
another's answers. Tokens come from real logins, never minted, except the
forged ones that test the token check itself.

Run from packages/fhirant_server:
  python3 -I tool/review_2026-10-17/access_grid.py <server-binary> <workdir>

Writes one row per request to tool/review_2026-10-17/access_grid.tsv as it
goes, and the seeded ids to access_grid_seed.json.
"""
import base64
import hashlib
import hmac
import http.client
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'access_grid.tsv')
SEED_OUT = os.path.join(HERE, 'access_grid_seed.json')
SPEC = os.path.abspath(os.path.join(HERE, '..', '..', 'assets', 'fhir_spec'))
ROUTER_SOURCE = os.path.abspath(
    os.path.join(HERE, '..', '..', 'lib', 'src', 'fhirant_server.dart'))

KEY = 'grid-key-' + 'a' * 32
SECRET = 'grid-jwt-secret-' + 'b' * 48
ROOT = ('root', 'Correct-Horse-Battery-9')
PW = 'Another-Long-Passw0rd!'
PORT = 18411

# Every identity logs in from its own loopback address, so the credential
# limiter (10 per 60 s per address) never decides a row.
ROOT_IP = '127.0.0.2'
GRID_IP = '127.0.0.3'


def log(row):
    with open(OUT, 'a') as f:
        f.write('\t'.join(str(c) for c in row) + '\n')
        f.flush()
    print('\t'.join(str(c) for c in row), flush=True)


def req(method, path, body=None, token=None, headers=None, ip=GRID_IP,
        timeout=60):
    """One request with a raw path (no client-side normalisation)."""
    h = {'Accept': 'application/fhir+json'}
    data = None
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode()
            h['Content-Type'] = 'application/fhir+json'
        else:
            data = body.encode()
            h['Content-Type'] = 'application/x-www-form-urlencoded'
    if token:
        h['Authorization'] = 'Bearer ' + token
    if headers:
        h.update(headers)
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=timeout,
                                   source_address=(ip, 0))
    try:
        c.request(method, path, body=data, headers=h)
        r = c.getresponse()
        b = r.read()
        return r.status, dict(r.getheaders()), b.decode('utf-8', 'replace')
    finally:
        c.close()


def start(dbdir, cwd):
    env = dict(os.environ)
    env.update({
        'FHIRANT_ENCRYPTION_KEY': KEY,
        'FHIRANT_JWT_SECRET': SECRET,
        'FHIRANT_ADMIN_USERNAME': ROOT[0],
        'FHIRANT_ADMIN_PASSWORD': ROOT[1],
    })
    logf = open(os.path.join(cwd, 'server.log'), 'w')
    p = subprocess.Popen(
        [BIN, '--port', str(PORT), '--db-path', dbdir, '--spec-path', SPEC],
        cwd=cwd, env=env, stdout=logf, stderr=subprocess.STDOUT)
    with open(os.path.join(cwd, 'pid'), 'w') as f:
        f.write(str(p.pid))
    for _ in range(120):
        try:
            if req('GET', '/health', ip=ROOT_IP, timeout=2)[0] == 200:
                return p
        except OSError:
            pass
        if p.poll() is not None:
            raise RuntimeError('server exited %s' % p.returncode)
        time.sleep(0.5)
    p.kill()
    raise RuntimeError('server did not answer /health in 60 s')


def stop(p):
    p.send_signal(signal.SIGINT)
    try:
        p.wait(20)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()


def login(user, pw, ip):
    s, _, b = req('POST', '/auth/login', {'username': user, 'password': pw},
                  ip=ip)
    if s != 200:
        raise RuntimeError('login %s: %s %s' % (user, s, b[:200]))
    j = json.loads(b)
    return j['token'], j.get('refresh_token')


def b64(d):
    return base64.urlsafe_b64encode(d).rstrip(b'=').decode()


def unb64(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def sign(header, claims, secret):
    h = b64(json.dumps(header).encode())
    c = b64(json.dumps(claims).encode())
    sig = hmac.new(secret.encode(), ('%s.%s' % (h, c)).encode(),
                   hashlib.sha256).digest()
    return '%s.%s.%s' % (h, c, b64(sig))


def claims_of(token):
    return json.loads(unb64(token.split('.')[1]))


# --- the seeded store ------------------------------------------------------

USERS = [
    # username, role, scopes, patient
    ('adm2', 'admin', None, None),
    ('clin', 'clinician', None, None),
    ('rdonly', 'readonly', None, None),
    ('pat', 'clinician', ['patient/*.*'], 'pat1'),
    ('patro', 'readonly', ['patient/*.rs'], 'pat1'),
    ('deact', 'clinician', None, None),
    ('demo', 'admin', None, None),
    ('pwch', 'clinician', None, None),
    ('narrow', 'clinician', None, None),
    ('loggedout', 'clinician', None, None),
    ('target', 'clinician', None, None),
]

OUT_MARK = 'LEAKMARKOUT'   # every out-of-compartment fixture carries it
IN_MARK = 'INMARKPAT1'     # every in-compartment fixture carries it


def fixtures():
    def obs(i, pat, mark):
        return {'resourceType': 'Observation', 'id': i, 'status': 'final',
                'code': {'coding': [{'system': 'http://loinc.org',
                                     'code': '8867-4'}], 'text': mark},
                'subject': {'reference': 'Patient/' + pat},
                'identifier': [{'system': 'urn:grid', 'value': i}]}
    return [
        {'resourceType': 'Patient', 'id': 'pat1',
         'name': [{'family': IN_MARK}]},
        {'resourceType': 'Patient', 'id': 'pat2',
         'name': [{'family': OUT_MARK}]},
        obs('obs1', 'pat1', IN_MARK),
        obs('obs2', 'pat2', OUT_MARK),
        obs('obs2b', 'pat2', OUT_MARK),
        {'resourceType': 'Encounter', 'id': 'enc1', 'status': 'finished',
         'class': {'code': 'AMB'}, 'subject': {'reference': 'Patient/pat1'},
         'serviceType': {'text': IN_MARK}},
        {'resourceType': 'Encounter', 'id': 'enc2', 'status': 'finished',
         'class': {'code': 'AMB'}, 'subject': {'reference': 'Patient/pat2'},
         'serviceType': {'text': OUT_MARK}},
        {'resourceType': 'Composition', 'id': 'comp1', 'status': 'final',
         'type': {'text': 'note'}, 'date': '2026-10-17',
         'author': [{'display': 'x'}], 'title': IN_MARK,
         'subject': {'reference': 'Patient/pat1'},
         'section': [{'entry': [{'reference': 'Observation/obs1'}]}]},
        {'resourceType': 'Composition', 'id': 'comp2', 'status': 'final',
         'type': {'text': 'note'}, 'date': '2026-10-17',
         'author': [{'display': 'x'}], 'title': OUT_MARK,
         'subject': {'reference': 'Patient/pat2'},
         'section': [{'entry': [{'reference': 'Observation/obs2'}]}]},
        {'resourceType': 'Group', 'id': 'g1', 'type': 'person',
         'actual': True, 'name': OUT_MARK,
         'member': [{'entity': {'reference': 'Patient/pat1'}},
                    {'entity': {'reference': 'Patient/pat2'}}]},
        {'resourceType': 'Library', 'id': 'lib1', 'status': 'active',
         'url': 'urn:grid:lib1', 'type': {'coding': [{
             'system': 'http://terminology.hl7.org/CodeSystem/library-type',
             'code': 'logic-library'}]},
         'content': [{'contentType': 'text/cql', 'data': base64.b64encode(
             b"library Grid version '1'\nusing FHIR version '4.0.1'\n"
             b"context Patient\ndefine Name: Patient.name\n").decode()}]},
        {'resourceType': 'Immunization', 'id': 'imm2', 'status': 'completed',
         'vaccineCode': {'coding': [{'system': 'http://hl7.org/fhir/sid/cvx',
                                     'code': '08'}], 'text': OUT_MARK},
         'patient': {'reference': 'Patient/pat2'},
         'occurrenceDateTime': '2020-01-01'},
    ]


def seed(work):
    d = os.path.join(work, 'seed')
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    p = start(os.path.join(d, 'db'), d)
    try:
        root, _ = login(*ROOT, ip=ROOT_IP)
        ids = {}
        for u, role, scopes, pat in USERS:
            body = {'username': u, 'password': PW, 'role': role}
            if scopes:
                body['scopes'] = scopes
            if pat:
                body['patient'] = pat
            # /auth/register is credential-limited per address.
            s, _, b = req('POST', '/auth/register', body, root,
                          ip='127.0.2.%d' % (len(ids) + 10))
            ids[u] = None
            assert s in (200, 201), (u, s, b)
        s, _, b = req('GET', '/admin/users', token=root, ip=ROOT_IP)
        for row in json.loads(b)['users'] if b.startswith('{') else json.loads(b):
            ids[row['username']] = row['id']
        for r in fixtures():
            s, _, b = req('PUT', '/%s/%s' % (r['resourceType'], r['id']), r,
                          root, ip=ROOT_IP)
            assert s in (200, 201), (r['id'], s, b[:300])
        # A finished export job owned by root, for the owner-checked routes.
        s, h, b = req('GET', '/$export?_type=Patient', token=root,
                      headers={'Prefer': 'respond-async'}, ip=ROOT_IP)
        loc = h.get('Content-Location') or h.get('content-location')
        assert s == 202 and loc, (s, h, b[:300])
        job = loc.rstrip('/').split('/')[-1]
        files = []
        for _ in range(120):
            s, _, b = req('GET', '/$export-poll-status/' + job, token=root,
                          ip=ROOT_IP)
            if s == 200:
                files = [o['url'] for o in json.loads(b)['output']]
                break
            time.sleep(0.5)
        assert files, 'export never finished'
        s, _, b = req('GET', '/AuditEvent?_count=1', token=root, ip=ROOT_IP)
        audit = json.loads(b)['entry'][0]['resource']['id']
        seedinfo = {'users': ids, 'job': job, 'file': files[0].split(
            '/$export-file/')[1], 'audit': audit}
        with open(SEED_OUT, 'w') as f:
            json.dump(seedinfo, f, indent=1)
        return seedinfo
    finally:
        stop(p)


# --- the requests ----------------------------------------------------------

def requests_for(seedinfo, me):
    """(label, method, path, body, extra headers). `me` is the identity's
    own credentials, for the routes that act on the caller."""
    t = seedinfo['users']['target']
    job, fil, audit = seedinfo['job'], seedinfo['file'], seedinfo['audit']
    q = urllib.parse.quote
    gender_vs = q('http://hl7.org/fhir/ValueSet/administrative-gender')
    gender_cs = q('http://hl7.org/fhir/administrative-gender')
    obs_put = {'resourceType': 'Observation', 'status': 'final',
               'code': {'text': 'grid'},
               'subject': {'reference': 'Patient/pat2'}}
    obs_in = dict(obs_put, subject={'reference': 'Patient/pat1'})
    patch = '[{"op":"replace","path":"/status","value":"amended"}]'
    meta = {'resourceType': 'Parameters', 'parameter': [{
        'name': 'meta', 'valueMeta': {'tag': [{'system': 'urn:g',
                                               'code': 'x'}]}}]}
    rows = [
        # auth/*
        ('status', 'GET', '/auth/status', None, None),
        ('register-admin', 'POST', '/auth/register',
         {'username': 'evil-' + me['name'], 'password': PW, 'role': 'admin'},
         None),
        ('login-bad', 'POST', '/auth/login',
         {'username': 'nobody', 'password': 'wrong-password-1'}, None),
        ('refresh-own', 'POST', '/auth/token',
         'grant_type=refresh_token&refresh_token=' + (me['refresh'] or ''),
         None),
        ('revoke-own', 'POST', '/auth/revoke',
         {'token': me['refresh'] or ''}, None),
        ('authorize-get', 'GET', '/auth/authorize?response_type=code&client_id'
         '=grid&redirect_uri=http%3A%2F%2F127.0.0.1%3A9%2Fcb&scope=patient%2F'
         '*.rs&state=s&code_challenge=' + 'A' * 43 +
         '&code_challenge_method=S256', None, None),
        ('authorize-post', 'POST', '/auth/authorize',
         {'username': 'clin', 'password': 'wrong-password-1',
          'client_id': 'grid', 'redirect_uri': 'http://127.0.0.1:9/cb',
          'response_type': 'code', 'code_challenge': 'A' * 43,
          'code_challenge_method': 'S256'}, None),
        # admin/*
        ('unlock', 'POST', '/admin/unlock/%d' % t, None, None),
        ('users', 'GET', '/admin/users', None, None),
        ('reset-pw', 'POST', '/admin/users/%d/password' % t,
         {'new_password': PW + 'reset'}, None),
        ('set-scopes', 'PUT', '/admin/users/%d/scopes' % t,
         {'scopes': ['user/*.*']}, None),
        ('set-role', 'PUT', '/admin/users/%d/role' % t, {'role': 'admin'},
         None),
        ('deactivate', 'POST', '/admin/users/%d/deactivate' % t, None, None),
        ('activate', 'POST', '/admin/users/%d/activate' % t, None, None),
        # public
        ('base', 'GET', '/', None, None),
        ('favicon', 'GET', '/favicon.ico', None, None),
        ('health', 'GET', '/health', None, None),
        ('metadata', 'GET', '/metadata', None, None),
        ('smart-config', 'GET', '/.well-known/smart-configuration', None,
         None),
        ('ws-plain-get', 'GET', '/ws', None, None),
        # CQL
        ('lib-eval-out', 'POST', '/Library/lib1/$evaluate',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'subject', 'valueString': 'Patient/pat2'}]}, None),
        ('lib-eval-url-out', 'POST', '/Library/$evaluate',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'url', 'valueString': 'urn:grid:lib1'},
             {'name': 'subject', 'valueString': 'Patient/pat2'}]}, None),
        ('cql-out', 'POST', '/$cql',
         {'cql': "library X version '1'\nusing FHIR version '4.0.1'\n"
                 "context Patient\ndefine N: Patient.name",
          'subject': 'Patient/pat2'}, None),
        # validation
        ('validate-sys', 'POST', '/$validate',
         {'resourceType': 'Patient', 'id': 'v'}, None),
        ('validate-type', 'POST', '/Patient/$validate',
         {'resourceType': 'Patient', 'id': 'v'}, None),
        ('validate-type-get', 'GET', '/Patient/$validate', None, None),
        # terminology
        ('vs-expand', 'GET', '/ValueSet/$expand?url=' + gender_vs, None,
         None),
        ('vs-expand-id', 'GET', '/ValueSet/administrative-gender/$expand',
         None, None),
        ('vs-expand-post', 'POST', '/ValueSet/$expand',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'url', 'valueUri':
              'http://hl7.org/fhir/ValueSet/administrative-gender'}]}, None),
        ('vs-expand-id-post', 'POST',
         '/ValueSet/administrative-gender/$expand',
         {'resourceType': 'Parameters', 'parameter': []}, None),
        ('vs-validate', 'GET', '/ValueSet/$validate-code?url=%s&system=%s'
         '&code=male' % (gender_vs, gender_cs), None, None),
        ('vs-validate-id', 'GET', '/ValueSet/administrative-gender/'
         '$validate-code?system=%s&code=male' % gender_cs, None, None),
        ('vs-validate-post', 'POST', '/ValueSet/$validate-code',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'url', 'valueUri':
              'http://hl7.org/fhir/ValueSet/administrative-gender'},
             {'name': 'code', 'valueCode': 'male'},
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'}]}, None),
        ('vs-validate-id-post', 'POST',
         '/ValueSet/administrative-gender/$validate-code',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'code', 'valueCode': 'male'},
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'}]}, None),
        ('cs-validate', 'GET', '/CodeSystem/$validate-code?url=%s&code=male'
         % gender_cs, None, None),
        ('cs-validate-id', 'GET', '/CodeSystem/administrative-gender/'
         '$validate-code?code=male', None, None),
        ('cs-validate-post', 'POST', '/CodeSystem/$validate-code',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'url', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'},
             {'name': 'code', 'valueCode': 'male'}]}, None),
        ('cs-validate-id-post', 'POST',
         '/CodeSystem/administrative-gender/$validate-code',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'code', 'valueCode': 'male'}]}, None),
        ('cs-lookup', 'GET', '/CodeSystem/$lookup?system=%s&code=male'
         % gender_cs, None, None),
        ('cs-lookup-id', 'GET', '/CodeSystem/administrative-gender/$lookup'
         '?code=male', None, None),
        ('cs-lookup-post', 'POST', '/CodeSystem/$lookup',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'},
             {'name': 'code', 'valueCode': 'male'}]}, None),
        ('cs-lookup-id-post', 'POST',
         '/CodeSystem/administrative-gender/$lookup',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'code', 'valueCode': 'male'}]}, None),
        ('cs-subsumes', 'GET', '/CodeSystem/$subsumes?system=%s&codeA=male'
         '&codeB=male' % gender_cs, None, None),
        ('cs-subsumes-id', 'GET', '/CodeSystem/administrative-gender/'
         '$subsumes?codeA=male&codeB=male', None, None),
        ('cs-subsumes-post', 'POST', '/CodeSystem/$subsumes',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'},
             {'name': 'codeA', 'valueCode': 'male'},
             {'name': 'codeB', 'valueCode': 'male'}]}, None),
        ('cs-subsumes-id-post', 'POST',
         '/CodeSystem/administrative-gender/$subsumes',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'codeA', 'valueCode': 'male'},
             {'name': 'codeB', 'valueCode': 'male'}]}, None),
        ('ns-preferred', 'GET', '/NamingSystem/$preferred-id?id=2.16.840.1.'
         '113883.6.1&type=uri', None, None),
        ('ns-preferred-post', 'POST', '/NamingSystem/$preferred-id',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'id', 'valueString': '2.16.840.1.113883.6.1'},
             {'name': 'type', 'valueCode': 'uri'}]}, None),
        ('cm-translate', 'GET', '/ConceptMap/$translate?system=%s&code=male'
         % gender_cs, None, None),
        ('cm-translate-id', 'GET', '/ConceptMap/cm-administrative-gender-v2/'
         '$translate?system=%s&code=male' % gender_cs, None, None),
        ('cm-translate-post', 'POST', '/ConceptMap/$translate',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'},
             {'name': 'code', 'valueCode': 'male'}]}, None),
        ('cm-translate-id-post', 'POST',
         '/ConceptMap/cm-administrative-gender-v2/$translate',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'system', 'valueUri':
              'http://hl7.org/fhir/administrative-gender'},
             {'name': 'code', 'valueCode': 'male'}]}, None),
        # program operations
        ('fhirpath-get-out', 'GET', '/$fhirpath?expression=name&resourceType'
         '=Patient&resourceId=pat2', None, None),
        ('fhirpath-post-out', 'POST', '/$fhirpath?expression=name'
         '&resourceType=Patient&resourceId=pat2', None, None),
        ('forecast-out', 'POST', '/$immds-forecast',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'assessmentDate', 'valueDate': '2026-10-17'},
             {'name': 'patient', 'valueString': 'Patient/pat2'}]}, None),
        ('forecast-who-out', 'POST', '/$immds-forecast-who',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'assessmentDate', 'valueDate': '2026-10-17'},
             {'name': 'patient', 'valueString': 'Patient/pat2'}]}, None),
        ('transform', 'POST', '/$transform',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'source', 'valueUri': 'urn:none'}]}, None),
        # bulk
        ('export-sys', 'GET', '/$export?_type=Patient', None,
         {'Prefer': 'respond-async'}),
        ('export-group', 'GET', '/Group/g1/$export', None,
         {'Prefer': 'respond-async'}),
        ('export-patient', 'GET', '/Patient/$export', None,
         {'Prefer': 'respond-async'}),
        ('export-status-roots', 'GET', '/$export-poll-status/' + job, None,
         None),
        ('export-file-roots', 'GET', '/$export-file/' + fil, None,
         {'Accept': 'application/fhir+ndjson'}),
        # documents, compartments, everything
        ('document-out', 'GET', '/Composition/comp2/$document', None, None),
        ('document-in', 'GET', '/Composition/comp1/$document', None, None),
        ('everything-out', 'GET', '/Patient/pat2/$everything', None, None),
        ('everything-in', 'GET', '/Patient/pat1/$everything', None, None),
        ('everything-enc-out', 'GET', '/Encounter/enc2/$everything', None,
         None),
        ('meta-out', 'GET', '/Observation/obs2/$meta', None, None),
        ('meta-add-out', 'POST', '/Observation/obs2/$meta-add', meta, None),
        ('meta-delete-out', 'POST', '/Observation/obs2/$meta-delete', meta,
         None),
        # history
        ('vread-out', 'GET', '/Observation/obs2/_history/1', None, None),
        ('history-out', 'GET', '/Observation/obs2/_history', None, None),
        ('history-type', 'GET', '/Observation/_history', None, None),
        ('history-sys', 'GET', '/_history', None, None),
        # compartment
        ('compartment-out', 'GET', '/Patient/pat2/Observation', None, None),
        ('compartment-in', 'GET', '/Patient/pat1/Observation', None, None),
        ('compartment-enc-out', 'GET', '/Encounter/enc2/Observation', None,
         None),
        # search
        ('search-sys-post', 'POST', '/_search', '_type=Observation', None),
        ('search-type-post', 'POST', '/Observation/_search',
         'subject=Patient/pat2', None),
        ('search-type', 'GET', '/Observation', None, None),
        ('search-subject-out', 'GET', '/Observation?subject=Patient/pat2',
         None, None),
        ('search-chain-out', 'GET', '/Observation?subject:Patient.family='
         + OUT_MARK, None, None),
        ('search-has-out', 'GET', '/Patient?_has:Observation:subject:code='
         '8867-4', None, None),
        ('search-include-out', 'GET', '/Observation?code=8867-4&_include='
         'Observation:subject', None, None),
        ('search-revinclude', 'GET', '/Patient?_revinclude=Observation:'
         'subject', None, None),
        ('search-sys-get', 'GET', '/?_type=Observation', None, None),
        ('search-audit', 'GET', '/AuditEvent', None, None),
        # reads
        ('read-out', 'GET', '/Observation/obs2', None, None),
        ('read-in', 'GET', '/Observation/obs1', None, None),
        ('read-pat-out', 'GET', '/Patient/pat2', None, None),
        ('read-pat-in', 'GET', '/Patient/pat1', None, None),
        ('read-group', 'GET', '/Group/g1', None, None),
        ('read-imm-out', 'GET', '/Immunization/imm2', None, None),
        ('head-out', 'HEAD', '/Observation/obs2', None, None),
        ('options', 'OPTIONS', '/Observation', None, None),
        # outside the route list
        ('unknown-type', 'GET', '/Foo', None, None),
        ('unknown-type-id', 'GET', '/Foo/1', None, None),
        ('lower-type', 'GET', '/observation/obs2', None, None),
        ('double-slash', 'GET', '//Observation/obs2', None, None),
        ('trailing-slash', 'GET', '/Observation/obs2/', None, None),
        ('encoded-slash', 'GET', '/Observation%2Fobs2', None, None),
        ('dotdot-auth', 'GET', '/auth/../Observation/obs2', None, None),
        ('dotdot-auth-enc', 'GET', '/auth/%2e%2e/Observation/obs2', None,
         None),
        ('dotdot-wellknown', 'GET', '/.well-known/../Observation/obs2', None,
         None),
        ('dotdot-metadata', 'GET', '/metadata/../Observation/obs2', None,
         None),
        ('auth-prefix-unknown', 'GET', '/auth/x', None, None),
        ('auth-prefix-nested', 'GET', '/auth/x/Observation/obs2', None,
         None),
        ('wellknown-unknown', 'GET', '/.well-known/x', None, None),
        ('admin-unknown', 'GET', '/admin/x', None, None),
        ('unknown-op', 'POST', '/$nope', None, None),
        ('metadata-post', 'POST', '/metadata', {'x': 1}, None),
        ('health-query', 'GET', '/health?x=1', None, None),
        ('metadata-mode', 'GET', '/metadata?mode=terminology', None, None),
        ('override-delete', 'POST', '/Observation/obs2', None,
         {'X-HTTP-Method-Override': 'DELETE'}),
        ('override-get-search', 'POST', '/Observation/_search', '',
         {'X-HTTP-Method-Override': 'GET'}),
        # writes (after every read)
        ('bundle-batch-read-out', 'POST', '/',
         {'resourceType': 'Bundle', 'type': 'batch', 'entry': [
             {'request': {'method': 'GET', 'url': 'Observation/obs2'}},
             {'request': {'method': 'GET',
                          'url': 'Observation?subject=Patient/pat2'}}]},
         None),
        ('bundle-tx-write-out', 'POST', '/',
         {'resourceType': 'Bundle', 'type': 'transaction', 'entry': [
             {'resource': obs_put, 'request': {'method': 'POST',
                                               'url': 'Observation'}}]},
         None),
        ('create-out', 'POST', '/Observation', obs_put, None),
        ('create-in', 'POST', '/Observation', obs_in, None),
        ('create-searchparam', 'POST', '/SearchParameter',
         {'resourceType': 'SearchParameter', 'url': 'urn:grid:sp',
          'name': 'gridsp', 'status': 'active', 'description': 'x',
          'code': 'gridsp', 'base': ['Patient'], 'type': 'string',
          'expression': 'Patient.name.family'}, None),
        ('create-subscription-out', 'POST', '/Subscription',
         {'resourceType': 'Subscription', 'status': 'requested',
          'reason': 'grid', 'criteria': 'Observation?subject=Patient/pat2',
          'channel': {'type': 'rest-hook',
                      'endpoint': 'http://127.0.0.1:9/hook',
                      'payload': 'application/fhir+json'}}, None),
        ('update-out', 'PUT', '/Observation/obs2',
         dict(obs_put, id='obs2'), None),
        ('update-in', 'PUT', '/Observation/obs1',
         dict(obs_in, id='obs1'), None),
        ('update-create-out', 'PUT', '/Observation/newout',
         dict(obs_put, id='newout'), None),
        ('cond-update-out', 'PUT', '/Observation?identifier=urn:grid|obs2b',
         dict(obs_put, identifier=[{'system': 'urn:grid',
                                    'value': 'obs2b'}]), None),
        ('patch-out', 'PATCH', '/Observation/obs2', patch,
         {'Content-Type': 'application/json-patch+json'}),
        ('audit-update', 'PUT', '/AuditEvent/' + audit,
         {'resourceType': 'AuditEvent', 'id': audit, 'recorded':
          '2026-10-17T00:00:00Z', 'type': {'code': 'rest'},
          'agent': [{'requestor': True}],
          'source': {'observer': {'display': 'x'}}}, None),
        ('audit-delete', 'DELETE', '/AuditEvent/' + audit, None, None),
        ('delete-out', 'DELETE', '/Observation/obs2', None, None),
        ('cond-delete-out', 'DELETE', '/Observation?identifier=urn:grid|'
         'obs2b', None, None),
        ('delete-in', 'DELETE', '/Observation/obs1', None, None),
        ('export-delete-roots', 'DELETE', '/$export-poll-status/' + job,
         None, None),
        # system operations last
        ('reindex', 'POST', '/$reindex', None, None),
        ('reindex-status', 'GET', '/$reindex-status', None, None),
        ('backup', 'POST', '/$backup',
         {'resourceType': 'Parameters', 'parameter': [
             {'name': 'passphrase', 'valueString': 'grid-backup-passphrase'}]},
         None),
        ('restore-garbage', 'POST', '/$restore', 'not a backup',
         {'Content-Type': 'application/octet-stream'}),
        ('password-own', 'POST', '/auth/password',
         {'current_password': me['pw'], 'new_password': PW + 'x'}, None),
        ('logout', 'POST', '/auth/logout', None, None),
        ('after-logout-read', 'GET', '/Observation/obs1', None, None),
    ]
    return rows


def route_coverage(rows):
    """Every registered route must be hit by at least one row."""
    src = open(ROUTER_SOURCE).read()
    pat = re.compile(
        r"\.\.(get|post|put|delete|patch|all|head|mount|add)\(\s*r?'([^']+)'",
        re.S)
    routes = [(m.group(1).upper(), m.group(2)) for m in pat.finditer(src)]

    def rx(path):
        out = ''
        for part in re.split(r'(<[^>]+>)', path):
            out += '[^/]+' if part.startswith('<') else re.escape(part)
        return re.compile('^' + out + '$')
    missing = []
    for verb, path in routes:
        r = rx(path)
        hit = any(r.match(p.split('?')[0]) and (verb == 'ALL' or m == verb)
                  for _, m, p, _, _ in rows)
        if not hit:
            missing.append('%s %s' % (verb, path))
    return len(routes), missing


# --- identities ------------------------------------------------------------

def identity_setup(name, seedinfo, root):
    """Returns (token, refresh, password) for the identity, after whatever
    change to the account the identity is about."""
    ids = seedinfo['users']
    ip = '127.0.1.10'

    def as_root(m, p, b=None):
        s, _, body = req(m, p, b, root, ip=ROOT_IP)
        assert s < 300, (m, p, s, body[:300])
    if name == 'admin':
        a, r = login('adm2', PW, ip)
        return a, r, PW
    if name in ('clin', 'rdonly', 'pat', 'patro'):
        a, r = login(name, PW, ip)
        return a, r, PW
    if name == 'none':
        return None, None, PW
    c, cr = login('clin', PW, ip)
    if name == 'garbage':
        return 'abc.def.ghi', None, PW
    if name == 'wrong-secret':
        return sign({'alg': 'HS256', 'typ': 'JWT'}, claims_of(c),
                    'not-the-secret'), None, PW
    if name == 'alg-none':
        h = b64(json.dumps({'alg': 'none', 'typ': 'JWT'}).encode())
        k = b64(json.dumps(claims_of(c)).encode())
        return '%s.%s.' % (h, k), None, PW
    if name == 'refresh-as-access':
        return cr, cr, PW
    if name == 'expired':
        k = claims_of(c)
        k['exp'] = int(time.time()) - 60
        k['iat'] = int(time.time()) - 3600
        return sign({'alg': 'HS256', 'typ': 'JWT'}, k, SECRET), None, PW
    if name == 'deactivated':
        a, r = login('deact', PW, ip)
        as_root('POST', '/admin/users/%d/deactivate' % ids['deact'])
        return a, r, PW
    if name == 'demoted':
        a, r = login('demo', PW, ip)
        as_root('PUT', '/admin/users/%d/role' % ids['demo'],
                {'role': 'readonly'})
        return a, r, PW
    if name == 'pw-reset':
        a, r = login('pwch', PW, ip)
        as_root('POST', '/admin/users/%d/password' % ids['pwch'],
                {'new_password': PW + 'reset'})
        return a, r, PW
    if name == 'scopes-narrowed':
        a, r = login('narrow', PW, ip)
        as_root('PUT', '/admin/users/%d/scopes' % ids['narrow'],
                {'scopes': ['user/*.rs']})
        return a, r, PW
    if name == 'logged-out':
        a, r = login('loggedout', PW, ip)
        s, _, b = req('POST', '/auth/logout', {'refresh_token': r}, a, ip=ip)
        assert s == 200, (s, b)
        return a, r, PW
    raise ValueError(name)


IDENTITIES = ['admin', 'clin', 'rdonly', 'pat', 'patro', 'none', 'garbage',
              'wrong-secret', 'alg-none', 'refresh-as-access', 'expired',
              'deactivated', 'demoted', 'pw-reset', 'scopes-narrowed',
              'logged-out']


def main():
    global BIN
    BIN, work = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    os.makedirs(work, exist_ok=True)
    seedinfo = seed(work)
    print('seed', seedinfo, flush=True)
    probe_rows = requests_for(seedinfo, {'name': 'x', 'refresh': 'x',
                                         'pw': 'x'})
    n, missing = route_coverage(probe_rows)
    with open(OUT, 'w') as f:
        f.write('identity\tlabel\tmethod\tpath\tstatus\tout_mark\tin_mark'
                '\tbody\n')
    log(['#routes', n, 'uncovered', len(missing), ';'.join(missing), '', '',
         ''])
    for ident in IDENTITIES:
        if only and ident not in only:
            continue
        d = os.path.join(work, ident)
        shutil.rmtree(d, ignore_errors=True)
        shutil.copytree(os.path.join(work, 'seed'), d)
        p = start(os.path.join(d, 'db'), d)
        try:
            root, _ = login(*ROOT, ip=ROOT_IP)
            tok, ref, pw = identity_setup(ident, seedinfo, root)
            me = {'name': ident, 'refresh': ref, 'pw': pw}
            for label, m, path, body, hdr in requests_for(seedinfo, me):
                try:
                    s, _, b = req(m, path, body, tok, hdr)
                except Exception as e:  # a dropped connection is a result
                    s, b = 'EXC', repr(e)
                flat = b.replace('\t', ' ').replace('\n', ' ')
                log([ident, label, m, path, s, OUT_MARK in b, IN_MARK in b,
                     flat[:220]])
            # Did anything the identity sent create an account?
            s, _, b = req('GET', '/admin/users', token=root, ip=ROOT_IP)
            evil = [u for u in json.loads(b).get('users', [])
                    if u['username'].startswith('evil-')] if s == 200 else b
            log([ident, 'post:evil-accounts', '', '', s, '', '', evil])
        finally:
            stop(p)


if __name__ == '__main__':
    main()
