#!/usr/bin/env python3
"""R4B search.html probes (fifth fhirant review, 2026-10-17): handling of
errors and unknown parameters (3.1.1.3), the self link as the record of the
parameters used (3.1.1.6, SHALL), _query (3.1.1.7, SHALL refuse unknown),
and the result controls (3.1.1.5). Value semantics per parameter type were
audited 2026-09-06 (97 rows) and against HAPI (tool/differential); not
repeated here.

Run from packages/fhirant_server, after access_grid.py has seeded <workdir>:
  python3 -I tool/review_2026-10-17/search_probes.py <server> <workdir>
"""
import json
import os
import shutil
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access_grid as g  # noqa: E402

OUT = os.path.join(g.HERE, 'search_probes.tsv')


def log(case, rule, expected, observed, verdict):
    line = '\t'.join(str(x).replace('\t', ' ').replace('\n', ' ')[:400]
                     for x in (case, rule, expected, observed, verdict))
    with open(OUT, 'a') as f:
        f.write(line + '\n')
        f.flush()
    print(line, flush=True)


def main():
    g.BIN, work = sys.argv[1], sys.argv[2]
    open(OUT, 'w').write('case\trule\texpected\tobserved\tverdict\n')
    d = os.path.join(work, 'search')
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(os.path.join(work, 'seed'), d)
    p = g.start(os.path.join(d, 'db'), d)
    try:
        run()
    finally:
        g.stop(p)


def run():
    T, _ = g.login('adm2', g.PW, g.ROOT_IP)

    def s(path, headers=None):
        st, h, b = g.req('GET', path, token=T, headers=headers, ip=g.ROOT_IP)
        try:
            j = json.loads(b)
        except ValueError:
            j = {}
        return st, j, b

    def self_of(j):
        u = [x['url'] for x in j.get('link', []) if x['relation'] == 'self']
        return urllib.parse.unquote(u[0]) if u else None

    def ids(j):
        return sorted(e['resource']['id'] for e in j.get('entry', [])
                      if e.get('search', {}).get('mode', 'match') == 'match')

    _, base, _ = s('/Observation?_count=100')
    n_all = base.get('total')
    rule_self = ('SHALL return the parameters that were actually used to '
                 'process the search ... encoded in the self link')
    for case, q in [
            ('unknown parameter', 'subjekt=Patient/pat1'),
            ('typo of a real parameter', 'patiet=Patient/pat1'),
            ('known parameter, other type', 'birthdate=2000'),
            ('unknown + known', 'code=8867-4&subjekt=Patient/pat1')]:
        st, j, _ = s('/Observation?' + q)
        sl = self_of(j) or ''
        unk = q.split('&')[-1].split('=')[0]
        log('self link: %s' % case, rule_self, 'ignored param absent from '
            'self link (or 400)', (st, j.get('total'), 'of', n_all, sl),
            'FAIL' if st == 200 and unk in sl else 'PASS')
        st, j, b = s('/Observation?' + q, {'Prefer': 'handling=strict'})
        log('handling=strict: %s' % case, 'Prefer: handling=strict: Client '
            'requests that the server return an error for any unknown or '
            'unsupported parameter (SHOULD honor)', '4xx', (st, b[:120]),
            'PASS' if st >= 400 else 'FAIL')
    st, j, _ = s('/Observation?code=8867-4&_sort=-date')
    log('self link carries _sort', 'The server returns the sort it performs '
        'as part of the returned search parameters', '_sort in self',
        self_of(j), 'PASS' if '_sort' in (self_of(j) or '') else 'FAIL')
    st, j, _ = s('/Observation?_sort=not-a-param')
    log('self link: unknown _sort param', rule_self, 'absent or 4xx',
        (st, self_of(j)), 'FAIL' if st == 200 and 'not-a-param' in
        (self_of(j) or '') else 'PASS')
    st, j, b = s('/Observation?_query=nonesuch')
    log('_query unknown', 'Servers processing search requests SHALL refuse '
        'to process a search request if they do not recognize the _query '
        'parameter value', '4xx', (st, b[:120]),
        'PASS' if st >= 400 else 'FAIL')
    st, j, _ = s('/Observation?code=')
    log('empty parameter', 'Empty parameters are not an error - they are '
        'just ignored by the server', '200, total = all', (st, j.get('total'),
                                                           n_all),
        'PASS' if st == 200 and j.get('total') == n_all else 'FAIL')
    st, j, b = s('/Observation?date=23%20May%202009')
    log('bad date format', 'servers SHOULD return an error', '400',
        (st, b[:100]), 'PASS' if st == 400 else 'FAIL')
    st, j, b = s('/Observation?value-quantity=abc')
    log('bad quantity', 'syntactically incorrect -> error', '400',
        (st, b[:100]), 'PASS' if st == 400 else 'FAIL')
    st, j, _ = s('/Observation?subject=Patient/nobody')
    log('reference to nonexistent', 'SHOULD process the search ... '
        'returning an empty search set', '200 total 0', (st, j.get('total')),
        'PASS' if st == 200 and j.get('total') == 0 else 'FAIL')
    st, j, b = s('/Observation?code:text-bogus=x')
    log('illegal modifier', 'A parameter may use an illegal or unacceptable '
        'modifier', '4xx', (st, b[:100]), 'PASS' if st >= 400 else 'FAIL')
    st, j, b = s('/Observation?_count=0')
    log('_count=0', 'treated the same as _summary=count: total, no entries, '
        'no prev/next/last links', 'total, 0 entries, no next',
        (st, j.get('total'), len(j.get('entry', [])),
         [x['relation'] for x in j.get('link', [])]),
        'PASS' if st == 200 and j.get('total') == n_all and
        not j.get('entry') and not any(x['relation'] in ('next', 'last',
                                                         'previous')
                                       for x in j.get('link', []))
        else 'FAIL')
    st, j, b = s('/Observation?_summary=count')
    log('_summary=count', 'just return a count', 'total, 0 entries',
        (st, j.get('total'), len(j.get('entry', []))),
        'PASS' if j.get('total') == n_all and not j.get('entry') else 'FAIL')
    st, j, _ = s('/Observation?_count=2')
    nxt = [x['url'] for x in j.get('link', []) if x['relation'] == 'next']
    log('_count repeated in next link', 'The server should repeat the '
        'original _count parameter in its returned page links', '_count=2 '
        'in next', nxt, 'PASS' if nxt and '_count=2' in nxt[0] else 'FAIL')
    log('_count honoured', 'Servers SHALL NOT return more resources than '
        'requested', '<=2', len(j.get('entry', [])),
        'PASS' if len(j.get('entry', [])) <= 2 else 'FAIL')
    st, j, _ = s('/Observation?_count=2&_include=Observation:subject')
    m = [e for e in j.get('entry', []) if e.get('search', {}).get('mode')
         == 'match']
    inc = [e for e in j.get('entry', []) if e.get('search', {}).get('mode')
           == 'include']
    log('_count excludes includes', 'the _count parameter only applies to '
        'resources with entry.search.mode = search', '2 matches + includes',
        (len(m), len(inc)), 'PASS' if len(m) == 2 else 'FAIL')
    log('include mode', 'adds to the results, with the entry.search.mode '
        'set to "include"', 'every entry has a mode',
        [e.get('search', {}).get('mode') for e in j.get('entry', [])],
        'PASS' if all(e.get('search', {}).get('mode') in ('match',
                                                         'include')
                      for e in j.get('entry', [])) else 'FAIL')
    st, j, _ = s('/Observation?_include=*')
    log('_include=*', 'use the wild card "*" for the search parameter name',
        '200', (st, len(j.get('entry', []))), 'PASS' if st == 200 else
        'FAIL')
    st, j, _ = s('/Observation?_include:iterate=*&_revinclude:iterate=*')
    log('iterate wildcards', 'Servers are expected to limit the number of '
        'iterations', '200 bounded', (st, len(j.get('entry', []))), 'NOTE')
    st, j, b = s('/Observation?_include=Observation:not-a-param')
    log('_include unknown param', 'self link records what was used',
        'absent from self or 4xx', (st, self_of(j)),
        'FAIL' if st == 200 and 'not-a-param' in (self_of(j) or '')
        else 'PASS')
    for tot in ['none', 'estimate', 'accurate']:
        st, j, _ = s('/Observation?_total=' + tot)
        log('_total=%s' % tot, 'servers can ignore the _total parameter',
            'read', (st, j.get('total')), 'NOTE')
    st, j, _ = s('/Observation?_summary=true&_count=1')
    tags = [t.get('code') for e in j.get('entry', []) for t in
            e['resource'].get('meta', {}).get('tag', [])]
    log('_summary=true SUBSETTED', 'Servers SHOULD mark the resources with '
        'the tag SUBSETTED', 'SUBSETTED', tags,
        'PASS' if 'SUBSETTED' in tags else 'FAIL')
    st, j, b = s('/Observation?_summary=text&_include=Observation:subject')
    log('_summary=text with _include', 'the _include and _revinclude '
        'parameters cannot be mixed with _summary=text', '4xx',
        (st, b[:120]), 'PASS' if st >= 400 else 'FAIL')
    st, j, _ = s('/Observation?_elements=status&_count=1')
    tags = [t.get('code') for e in j.get('entry', []) for t in
            e['resource'].get('meta', {}).get('tag', [])]
    keys = [sorted(e['resource'].keys()) for e in j.get('entry', [])]
    log('_elements', 'Servers SHOULD always return mandatory elements ... '
        'SHOULD mark the resources with the tag SUBSETTED', 'status+code, '
        'SUBSETTED', (keys, tags), 'PASS' if 'SUBSETTED' in tags else 'FAIL')
    # _sort order
    st, j, _ = s('/Patient?_sort=family&_count=50')
    fams = [((e['resource'].get('name') or [{}])[0].get('family') or '')
            for e in j.get('entry', [])]
    log('_sort=family', 'SHOULD honor the _sort parameter; case-insensitive',
        'ascending', fams, 'PASS' if fams == sorted(fams, key=str.lower)
        else 'FAIL')
    st, j, b = s('/Patient?_sort=family,-birthdate')
    log('_sort multiple keys', 'comma-separated list of sort rules', '200',
        (st, b[:80]), 'PASS' if st == 200 else 'FAIL')
    # _contained
    g.req('PUT', '/MedicationRequest/mr1', {
        'resourceType': 'MedicationRequest', 'id': 'mr1', 'status': 'active',
        'intent': 'order', 'subject': {'reference': 'Patient/pat1'},
        'contained': [{'resourceType': 'Medication', 'id': 'm1', 'code': {
            'coding': [{'system': 'urn:x', 'code': 'abc'}]}}],
        'medicationReference': {'reference': '#m1'}}, T, ip=g.ROOT_IP)
    st, j, _ = s('/Medication?code=urn:x|abc')
    log('contained not returned by default', 'By default, search results '
        'only include resources that are not contained', 'total 0',
        (st, j.get('total')), 'PASS' if j.get('total') == 0 else 'FAIL')
    st, j, _ = s('/MedicationRequest?medication.code=urn:x|abc')
    log('chain into contained', 'A chained condition will be evaluated '
        'inside contained resources', 'mr1', (st, ids(j)),
        'PASS' if ids(j) == ['mr1'] else 'FAIL')
    st, j, b = s('/Medication?code=urn:x|abc&_contained=true')
    log('_contained=true', 'return only contained resources', 'm1 or 4xx',
        (st, b[:160]), 'NOTE')
    # _has, _type, _id, _lastUpdated, _tag, _profile, _security, _source,
    # _list, _text, _content, _filter: supported or refused, never ignored
    # silently with the parameter echoed.
    for q in ['_text=potassium', '_content=potassium', '_filter=status eq '
              'final', '_list=List/x', '_security=urn:x|y', '_source=urn:x',
              '_profile=http://x/y', '_tag=urn:x|y', '_lastUpdated=gt2000',
              '_id=obs1', '_has:Observation:subject:code=8867-4']:
        st, j, b = s('/Observation?' + urllib.parse.quote(q, safe='=:|/'))
        sl = self_of(j) or ''
        name = q.split('=')[0]
        log('common param %s' % name, rule_self, 'applied, or refused, or '
            'absent from self', (st, j.get('total'), sl[-60:]),
            'NOTE' if st != 200 else
            ('NOTE' if j.get('total') != n_all else
             ('FAIL' if name in sl else 'PASS')))


if __name__ == '__main__':
    main()
