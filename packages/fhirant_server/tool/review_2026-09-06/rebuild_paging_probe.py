"""REVIEW-2026-09-06 §6.1: the cost of paging the resources table for a
rebuild, OFFSET against keyset, isolated from the extraction. Runs against
the plain-SQLite MIMIC copy (fhirant.sqlite in <dir>); writes one row per
mode to <tsv> as each finishes.

    python3 rebuild_paging_probe.py <dir> <tsv>
"""
import sqlite3
import sys
import time

directory, tsv_path = sys.argv[1], sys.argv[2]
c = sqlite3.connect(f'{directory}/fhirant.sqlite')
out = open(tsv_path, 'w')
out.write('mode\tpages\trows\tms\n')
out.flush()


def offset_loop(cols):
    t = time.time()
    off = pages = rows = 0
    while True:
        r = c.execute(
            f'SELECT {cols} FROM resources ORDER BY resource_type, id '
            f'LIMIT 500 OFFSET {off}'
        ).fetchall()
        if not r:
            break
        off += len(r)
        pages += 1
        rows += len(r)
        if pages % 400 == 0:
            print(f'offset {cols}: page {pages} at {time.time() - t:.0f}s', flush=True)
    return pages, rows, (time.time() - t) * 1000


def keyset_loop(cols):
    t = time.time()
    last = ('', '')
    pages = rows = 0
    extra = f', {cols}' if cols else ''
    while True:
        r = c.execute(
            f'SELECT resource_type, id{extra} FROM resources '
            'WHERE (resource_type, id) > (?, ?) '
            'ORDER BY resource_type, id LIMIT 500',
            last,
        ).fetchall()
        if not r:
            break
        last = (r[-1][0], r[-1][1])
        pages += 1
        rows += len(r)
    return pages, rows, (time.time() - t) * 1000


for mode, fn, cols in [
    ('keyset ids only', keyset_loop, ''),
    ('offset ids only', offset_loop, 'resource_type, id'),
    ('keyset with json', keyset_loop, 'resource'),
    ('offset with json', offset_loop, 'resource'),
]:
    pages, rows, ms = fn(cols)
    out.write(f'{mode}\t{pages}\t{rows}\t{ms:.0f}\n')
    out.flush()
    print(f'{mode}: {pages} pages, {rows} rows, {ms:.0f} ms', flush=True)
