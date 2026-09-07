# Measurements, 2026-09-06

All on the MIMIC-IV-on-FHIR demo (`~/Downloads/mimic-iv-clinical-database-demo-on-fhir-2.1.0/fhir`,
928,935 resources), loaded with `tool/perf_load.dart`, searched with `tool/perf_search.dart`.

## Save path: the same 5,000 resources (`--limit 5000 --batch 500`)

| file | build | total |
|---|---|---|
| `ab_control.log` | fhirant `21d2775` on published fhir_r4_db 0.12.0 | 7.01 s |
| `ab_dev.log` | fhir_r4_db dev before the fix | 30.23 s |
| `ab_dev_nosubstr.log` | dev with only the `OR substr` half of the delete removed (cause isolated) | 7.25 s |
| `ab_dev_fixed.log` | dev, partial index + range delete with a BOUND `LIKE ?` (index not used) | 19.77 s |
| `ab_dev_fixed2.log` | dev, the same with a literal `LIKE '#%'` (the fix as committed) | 7.70 s |

## Full load on the fixed save path

`perf_load2.log` / `perffull.perf.tsv`: 928,935 in 1,480 s (628/s), 6.2 GB.

## Statistics

`analyze_run3.txt`: `sqlite_stat1` before (three empty partial indexes only) and after a full
ANALYZE (5.89 s). This is the "statistics gathered at create on empty tables" finding.

## Sort-index walk, A/B interleaved twice on the analysed database (`sort_ab.sh`)

| query | without walk (`nowalk`) | with walk |
|---|---|---|
| `subject(963) -date` | 0.04 / 0.04 s | 0.10 / 0.14 s |
| `subject(48k) -date` | 0.62 / 0.58 s | 8.05 / 7.91 s |
| `status=final -date` | 8.94 / 8.88 s | 8.48 / (see files) s |

The walk was removed. `status=final -date` at ~8.9 s is the open performance item.
Round 2 `nowalk` also carries a `database is locked` from a `perf_stats.dart` run that
overlapped it: `PRAGMA optimize` on open takes a write lock.
