#!/usr/bin/env python3
"""Run the same FHIR searches against fhirant and against HAPI FHIR, and
compare the answers.

The oracle this review needed: a mismatch is either our bug or a
difference we can name and defend. No review pass can do that.

    cd packages/fhirant_server && dart pub get      # once
    python3 tool/differential/run_differential.py   # from the repo root

Writes, from the repo root:
    tool/differential/results/cases.tsv     one row per search, as it runs
    tool/differential/results/run.log       what each step did
    tool/differential/results/<case>.json   both bodies, when they differ

fhirant is R4B and the HAPI image is R4. Every resource and search here is
one whose definition is identical in both, so a difference is not a version
difference. Anything version-specific belongs in KNOWN_DIFFERENCES with the
reason, or it is not tested here.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SERVER = REPO / 'packages' / 'fhirant_server'
OUT = REPO / 'tool' / 'differential' / 'results'

FHIRANT_PORT = 18500
HAPI_PORT = 18501
HAPI_CONTAINER = 'fhirant-differential-hapi'
HAPI_IMAGE = 'hapiproject/hapi:latest'

# A search whose answers differ for a reason we have named. Each entry is
# case name -> the reason. Nothing goes here without one.
KNOWN_DIFFERENCES: dict[str, str] = {}


def log(message: str) -> None:
    line = f'{time.strftime("%H:%M:%S")} {message}'
    print(line, flush=True)
    with (OUT / 'run.log').open('a') as fh:
        fh.write(line + '\n')
        fh.flush()


def request(
    method: str,
    url: str,
    body: dict | None = None,
    timeout: int = 60,
) -> tuple[int, dict | None, str]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Accept', 'application/fhir+json')
    if data is not None:
        req.add_header('Content-Type', 'application/fhir+json')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            text = response.read().decode()
            status = response.status
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        status = e.code
    except (urllib.error.URLError, TimeoutError) as e:
        return 0, None, str(e)
    try:
        return status, json.loads(text), text
    except json.JSONDecodeError:
        return status, None, text


# ── the two servers ────────────────────────────────────────────────────────


def start_fhirant() -> subprocess.Popen[bytes]:
    db = OUT / 'fhirant_db'
    if db.exists():
        shutil.rmtree(db)
    db.mkdir(parents=True)
    log(f'starting fhirant on {FHIRANT_PORT} (dev mode, empty store)')
    out = (OUT / 'fhirant_server.log').open('wb')
    process = subprocess.Popen(
        [
            'dart',
            'run',
            'bin/server.dart',
            '--dev-mode',
            '--port',
            str(FHIRANT_PORT),
            '--db-path',
            str(db),
            '--spec-path',
            str(SERVER / 'assets' / 'fhir_spec'),
            '--base-url',
            f'http://localhost:{FHIRANT_PORT}',
        ],
        cwd=SERVER,
        stdout=out,
        stderr=subprocess.STDOUT,
    )
    return process


def start_hapi() -> None:
    subprocess.run(
        ['docker', 'rm', '-f', HAPI_CONTAINER],
        capture_output=True,
        check=False,
    )
    log(f'starting HAPI on {HAPI_PORT}')
    subprocess.run(
        [
            'docker',
            'run',
            '-d',
            '--name',
            HAPI_CONTAINER,
            '-p',
            f'{HAPI_PORT}:8080',
            '-e',
            'hapi.fhir.fhir_version=R4',
            '-e',
            'hapi.fhir.allow_external_references=true',
            HAPI_IMAGE,
        ],
        check=True,
        capture_output=True,
    )


def wait_ready(base: str, name: str, seconds: int) -> bool:
    """Both servers answer /metadata when they are up."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        status, body, _ = request('GET', f'{base}/metadata', timeout=10)
        if status == 200 and body and body.get('resourceType'):
            log(f'{name} ready after {int(seconds - (deadline - time.time()))}s')
            return True
        time.sleep(3)
    log(f'{name} NOT ready after {seconds}s')
    return False


# ── the data ───────────────────────────────────────────────────────────────

FAMILIES = ['Faulkenberry', 'Okello', 'Nakato', 'Smith', 'Smithson']
GIVENS = ['Grey', 'John', 'Mary', 'Amina', 'Peter']
GENDERS = ['male', 'female', 'other', 'unknown']
BIRTHDATES = [
    '1974-12-25', '1980-01-01', '1999-06-15', '2010-03-08', '2020-11-30',
]
CODES = [
    ('http://loinc.org', '29463-7', 'Body weight'),
    ('http://loinc.org', '8302-2', 'Body height'),
    ('http://loinc.org', '8480-6', 'Systolic blood pressure'),
    ('http://snomed.info/sct', '271649006', 'Systolic blood pressure'),
]
OBS_DATES = [
    '2026-01-15T09:00:00Z', '2026-03-01T13:30:00Z', '2026-06-20T08:00:00Z',
    '2026-09-01T17:45:00Z', '2025-12-31T23:00:00Z',
]


def patients() -> list[dict]:
    out = []
    for i in range(20):
        out.append({
            'resourceType': 'Patient',
            'id': f'dp{i}',
            'identifier': [
                {'system': 'http://example.org/mrn', 'value': f'mrn-{i}'},
                # Every fourth patient also has an identifier with no system,
                # which is what `:identifier=|value` is about.
                *([{'value': f'bare-{i}'}] if i % 4 == 0 else []),
            ],
            'active': i % 5 != 0,
            'name': [{
                'family': FAMILIES[i % len(FAMILIES)],
                'given': [GIVENS[i % len(GIVENS)]],
            }],
            'gender': GENDERS[i % len(GENDERS)],
            'birthDate': BIRTHDATES[i % len(BIRTHDATES)],
        })
    return out


def observations() -> list[dict]:
    out = []
    for i in range(30):
        system, code, display = CODES[i % len(CODES)]
        out.append({
            'resourceType': 'Observation',
            'id': f'do{i}',
            'status': 'final' if i % 3 else 'preliminary',
            'code': {
                'coding': [
                    {'system': system, 'code': code, 'display': display},
                ],
                'text': display,
            },
            'subject': {'reference': f'Patient/dp{i % 20}'},
            'effectiveDateTime': OBS_DATES[i % len(OBS_DATES)],
            'valueQuantity': {
                'value': 50 + i,
                'unit': 'kg',
                'system': 'http://unitsofmeasure.org',
                'code': 'kg',
            },
        })
    return out


def load(base: str, name: str, resources: list[dict]) -> int:
    """PUT each resource, so both servers hold the same ids."""
    loaded = 0
    for resource in resources:
        status, _, text = request(
            'PUT',
            f'{base}/{resource["resourceType"]}/{resource["id"]}',
            resource,
        )
        if status in (200, 201):
            loaded += 1
        else:
            log(f'{name}: {resource["resourceType"]}/{resource["id"]} '
                f'-> {status} {text[:200]}')
    log(f'{name}: loaded {loaded}/{len(resources)}')
    return loaded


# ── the searches ───────────────────────────────────────────────────────────

CASES: list[tuple[str, str]] = [
    # name, query (path and parameters)
    ('string-default', 'Patient?family=Smith'),
    ('string-exact', 'Patient?family:exact=Smith'),
    ('string-contains', 'Patient?family:contains=ell'),
    ('string-case', 'Patient?family=smith'),
    ('string-accent', 'Patient?given=grey'),
    ('token-system-code', 'Observation?code=http://loinc.org|29463-7'),
    ('token-code-only', 'Observation?code=29463-7'),
    ('token-system-any', 'Observation?code=http://loinc.org|'),
    ('token-not', 'Observation?code:not=http://loinc.org|29463-7'),
    ('token-boolean', 'Patient?active=true'),
    ('token-gender', 'Patient?gender=female'),
    ('token-identifier', 'Patient?identifier=http://example.org/mrn|mrn-4'),
    ('token-identifier-value', 'Patient?identifier=mrn-4'),
    ('token-identifier-no-system', 'Patient?identifier=|bare-0'),
    ('date-eq', 'Patient?birthdate=1980-01-01'),
    ('date-gt', 'Patient?birthdate=gt2000-01-01'),
    ('date-le', 'Patient?birthdate=le1980-01-01'),
    ('date-year', 'Patient?birthdate=1999'),
    ('date-range-two', 'Patient?birthdate=ge1980-01-01&birthdate=le2010-12-31'),
    ('datetime-ge', 'Observation?date=ge2026-06-01'),
    ('datetime-eq-day', 'Observation?date=2026-03-01'),
    ('quantity-eq', 'Observation?value-quantity=60'),
    ('quantity-gt-unit', 'Observation?value-quantity=gt70|http://unitsofmeasure.org|kg'),
    ('reference-literal', 'Observation?subject=Patient/dp3'),
    ('reference-type', 'Observation?subject:Patient=dp3'),
    ('reference-bare-id', 'Observation?subject=dp3'),
    ('chain-family', 'Observation?subject.family=Smith'),
    ('chain-gender', 'Observation?patient.gender=male'),
    ('has', 'Patient?_has:Observation:subject:code=http://loinc.org|8302-2'),
    ('missing-true', 'Patient?birthdate:missing=true'),
    ('missing-false', 'Patient?birthdate:missing=false'),
    ('id-search', 'Patient?_id=dp7'),
    ('count-zero', 'Patient?_count=0'),
    ('sort-family', 'Patient?_sort=family'),
    ('sort-family-desc', 'Patient?_sort=-family'),
    ('sort-birthdate', 'Patient?_sort=birthdate'),
    ('page-five', 'Patient?_count=5&_sort=_id'),
    ('include-subject', 'Observation?code=http://loinc.org|8302-2&_include=Observation:subject'),
    ('revinclude', 'Patient?_id=dp3&_revinclude=Observation:subject'),
    ('summary-count', 'Patient?_summary=count'),
    ('total-accurate', 'Patient?_total=accurate'),
    ('and-two-params', 'Patient?gender=female&birthdate=1999-06-15'),
    ('or-comma', 'Patient?gender=female,male'),
    ('type-all', 'Observation'),
    # Boundaries. A search value's implicit range is what the prefixes
    # compare against (R4B 3.1.1.4.5), so a target equal to the value is the
    # case that tells `gt` from `ge`. do20 is exactly 70 kg; dp1 was born
    # 1980-01-01.
    ('quantity-gt-boundary', 'Observation?value-quantity=gt70'),
    ('quantity-ge-boundary', 'Observation?value-quantity=ge70'),
    ('quantity-lt-boundary', 'Observation?value-quantity=lt70'),
    ('quantity-le-boundary', 'Observation?value-quantity=le70'),
    ('quantity-eq-boundary', 'Observation?value-quantity=70'),
    ('quantity-ne-boundary', 'Observation?value-quantity=ne70'),
    ('quantity-decimal', 'Observation?value-quantity=gt69.5'),
    ('date-gt-boundary', 'Patient?birthdate=gt1980-01-01'),
    ('date-ge-boundary', 'Patient?birthdate=ge1980-01-01'),
    ('date-lt-boundary', 'Patient?birthdate=lt1980-01-01'),
    ('date-le-boundary', 'Patient?birthdate=le1980-01-01'),
    ('date-ne-boundary', 'Patient?birthdate=ne1980-01-01'),
    ('datetime-gt-boundary', 'Observation?date=gt2026-03-01T13:30:00Z'),
    ('datetime-ge-boundary', 'Observation?date=ge2026-03-01T13:30:00Z'),
    ('datetime-sa', 'Observation?date=sa2026-03-01'),
    ('datetime-eb', 'Observation?date=eb2026-03-01'),
    # A sort key that names no search parameter. HAPI refuses it; fhirant
    # answered 200 when the harness sent one by accident.
    ('sort-unknown-key', 'Patient?_sort=not-a-search-parameter'),
]


def ids_of(bundle: dict | None) -> list[str]:
    if not bundle or bundle.get('resourceType') != 'Bundle':
        return []
    out = []
    for entry in bundle.get('entry') or []:
        resource = entry.get('resource') or {}
        mode = ((entry.get('search') or {}).get('mode')) or 'match'
        rid = f'{resource.get("resourceType")}/{resource.get("id")}'
        out.append(rid if mode == 'match' else f'~{rid}')
    return out


def pinned(query: str) -> str:
    """The query with an order and a page big enough for every fixture.

    Unsorted order is not specified, and neither is the order of rows that
    tie on the sort key, so two servers may return different pages of the
    same answer. Every case is asked with `_sort=_id` (appended after the
    case's own sort key, where it has one) and `_count=100`, which is more
    than the 50 fixtures. The first run compared pages instead and called
    four agreements differences.
    """
    if '_summary=count' in query or '_count=0' in query:
        return query
    extra = []
    if '_sort=' in query:
        query = re.sub(r'(_sort=[^&]*)', r'\1,_id', query)
    else:
        extra.append('_sort=_id')
    # A case that sets its own _count keeps it: a second _count made one
    # server read 5 and the other 100 (page-five, first pinned run).
    if '_count=' not in query:
        extra.append('_count=100')
    if not extra:
        return query
    # One joiner for the whole tail. Two of them turned the sort value into
    # `_id?_count=100`, which HAPI refused and fhirant answered 200.
    joiner = '&' if '?' in query else '?'
    return query + joiner + '&'.join(extra)


def compare(name: str, query: str) -> tuple[str, str]:
    """Returns (verdict, detail)."""
    asked = pinned(query)
    a_status, a_body, a_text = request(
        'GET', f'http://localhost:{FHIRANT_PORT}/{asked}')
    b_status, b_body, b_text = request(
        'GET', f'http://localhost:{HAPI_PORT}/fhir/{asked}')

    a_ids, b_ids = ids_of(a_body), ids_of(b_body)
    a_total = (a_body or {}).get('total')
    b_total = (b_body or {}).get('total')

    # A refusal on both sides is agreement, whatever the wording.
    if a_status >= 400 and b_status >= 400:
        return 'both-refuse', f'{a_status}/{b_status}'
    if a_status >= 400 or b_status >= 400:
        detail = f'fhirant {a_status}, hapi {b_status}'
        (OUT / f'{name}.json').write_text(
            json.dumps(
                {'query': query, 'fhirant': a_text[:8000],
                 'hapi': b_text[:8000]},
                indent=2,
            )
        )
        return 'one-refuses', detail

    # _sort cases compare order; the rest compare sets.
    ordered = '_sort' in query
    same = (a_ids == b_ids) if ordered else (sorted(a_ids) == sorted(b_ids))
    # HAPI omits `total` on a paged result, so it is compared only when both
    # sent one.
    totals_agree = a_total is None or b_total is None or a_total == b_total
    if same and totals_agree:
        return 'match', f'{len(a_ids)} entries, total {a_total}/{b_total}'
    (OUT / f'{name}.json').write_text(
        json.dumps(
            {
                'query': query,
                'fhirant': {'total': a_total, 'ids': a_ids},
                'hapi': {'total': b_total, 'ids': b_ids},
            },
            indent=2,
        )
    )
    only_a = sorted(set(a_ids) - set(b_ids))
    only_b = sorted(set(b_ids) - set(a_ids))
    return 'differ', (
        f'total {a_total} vs {b_total}; only fhirant {only_a[:6]}; '
        f'only hapi {only_b[:6]}'
    )


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'run.log').write_text('')
    cases_file = (OUT / 'cases.tsv').open('w')
    cases_file.write('case\tverdict\tdetail\tquery\n')
    cases_file.flush()

    fhirant = start_fhirant()
    start_hapi()
    try:
        ok_a = wait_ready(f'http://localhost:{FHIRANT_PORT}', 'fhirant', 240)
        ok_b = wait_ready(f'http://localhost:{HAPI_PORT}/fhir', 'hapi', 420)
        if not (ok_a and ok_b):
            return 1

        resources = patients() + observations()
        for base, name in (
            (f'http://localhost:{FHIRANT_PORT}', 'fhirant'),
            (f'http://localhost:{HAPI_PORT}/fhir', 'hapi'),
        ):
            if load(base, name, resources) != len(resources):
                log(f'{name}: not every resource loaded; comparisons below '
                    'are against an incomplete store')

        counts = {'match': 0, 'differ': 0, 'both-refuse': 0, 'one-refuses': 0}
        for case_name, query in CASES:
            verdict, detail = compare(case_name, query)
            counts[verdict] = counts.get(verdict, 0) + 1
            if case_name in KNOWN_DIFFERENCES and verdict != 'match':
                detail = f'{detail} [known: {KNOWN_DIFFERENCES[case_name]}]'
            cases_file.write(f'{case_name}\t{verdict}\t{detail}\t{query}\n')
            cases_file.flush()
            log(f'{case_name}: {verdict} — {detail}')

        log(f'done: {counts}')
        return 0
    finally:
        cases_file.close()
        fhirant.terminate()
        try:
            fhirant.wait(timeout=20)
        except subprocess.TimeoutExpired:
            fhirant.kill()
        subprocess.run(
            ['docker', 'rm', '-f', HAPI_CONTAINER],
            capture_output=True,
            check=False,
        )
        log('both servers stopped')


if __name__ == '__main__':
    sys.exit(main())
