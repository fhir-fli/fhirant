# Storage floor and database size, 2026-11-01/02

Measurements behind `services/storage_floor.dart` (OWASP ASVS 5.0.0 V5.2.4)
and the questions Grey asked on the way: where the space goes, how fast a
phone fills, and why loading got slower. The scripts were run from
`/tmp/claude-1000/dbsize/`; their paths are as run.

## Where a database's space goes

`dbstat.tsv` (`tools/dbstat.py`): the full MIMIC-IV demo, 928,935 resources,
829 MB of NDJSON (`mimic_sizes.tsv`), loaded on main 1acc767 with fhir_db
0.15.2: 6.18 GB. The `resources` table is 1.07 GB (17%); history is empty (a
load writes one version); the search index tables and their indexes are the
other 83%. 6.65 KB on disk per resource.

Compression of single resources (`tools/gzip_ratio.py`,
`tools/deflate_dict.py`): deflate 2.02×, deflate with a 32 KiB preset
dictionary per file 5.17×. HAPI stores resources gzipped (`JSONC`, its
`schema.md`). Not pursued: history is a small share, and Grey ruled records
will not fill a phone (19,000 Idai visits ≈ 8.3 GB, derived).

`idai_sizes.tsv` (`tools/res_sizes.py`): Bumblebee's Idai oracle day, 3.72
resources per visit, 287 bytes mean; synthetic and bare.

## The floor's own costs

- `probe.tsv` (`tools/statvfs_probe.dart`): `statvfs` through FFI gives the
  size `df` reports; 4–6 µs a call, 15 µs for a path that does not exist yet.
- `sum_cost.txt`: summing the current resources' JSON on the 6.18 GB
  database, 2.88 s cold, 0.66 s warm (a MIMIC load was running beside it).

## Why loading slowed (`load_ab/`)

Full MIMIC load: 1,423 s on 2026-09-06, 2,475 s on 2026-10-30, 2,191 s on
2026-11-01 (`rates_compare.tsv`, `tools/compare_rates.py`). Only the two
largest Observation files slowed.

`sep_vs_now_100k.tsv` (`tools/ab_load.sh`): 100,000 chart observations into
an empty database, September's code (fhirant 852d697 + fhir_r4 0d582fec2)
against main, interleaved: September 103–116 s (round 1, 217 s, was
disturbed mid-run: its second half took 3× its first), main 183–199 s. Same
size (644/650 MB) and the same 1,173,464 index rows. `strace_*.txt`, 20,000
resources: main makes 2.4× the `pwrite`s and 2.7× the `pread`s.

`covers_vs_narrow.tsv` (`tools/ab_index.sh`): one variable, main's code with
its 16 covering value indexes against September's single-column ones
(`idx_sep.txt`, `idx_now.txt`): 20,000 resources 22.4–22.9 s against
14.1–14.4 s (September's code: 16.1–17.4 s); 100,000 with the narrow set:
83.0 s. The covering indexes (fhir_db bea5283, 2026-09-09, added for search
speed) are the whole slowdown, and their cost grows with the database.

Not measured yet: a load with the covers built once at the end
(`tools/load_then_index.sh`). Its first run overlapped the full test suite
and was stopped.
