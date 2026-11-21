# What one `$sync` costs, measured 2026-11-20

`run.sh N`: server A (CLI, dev mode) holds N MIMIC-IV resources loaded by
`perf_load.dart --server-store`; server B is empty and runs `$sync` with A as
its peer. Then a sync with nothing changed, then one after 100 Patients
changed on A. Times are the job's own `started`/`finished`
(`status_*.json`). Run b changed three things at once; from c on, each
row changes one thing from the row above it.

| run | code | first sync | nothing changed | 100 changed |
|---|---|---|---|---|
| a | each resource's history read and written on its own; `meta.source` added | 1,227 s | 620 s | 6.5 s |
| b | copies taken from the history pages, sent 500 to a batch; `meta.source` left alone; a sync's own writes not read again | 236 s | 6.5 s | 3.8 s |
| c | copies sent as a transaction | 130 s | 6.2 s | 3.7 s |
| d | the pairs of a Bundle recorded in one commit | 25.6 s | 10.2 s | 3.8 s |
| e | the pairs of 500 keys read in one query | 22.5 s | 5.3 s | 3.4 s |

All 10,000 written in each first sync, no failures. One run of each: how
much a time varies between runs was not measured (c to d, which did not
touch the no-change path, went 6.2 s to 10.2 s).

- Run a was held by A's rate limit (1,000 requests a minute in dev mode,
  600 otherwise): 20,128 requests to A in the first 1,207 s, two per
  resource (its history, and a write back). The write back came from the
  sync adding `meta.source`, of which R4B resource.html says "the server
  SHOULD generally leave this unchanged"; it made A's copy differ from B's, so A got a
  new version of every resource, and the next sync read them all again.
- From run b on, a first sync makes 21 requests to A (its history pages).
  In run b each 500 took ~11 s to write here; `batch_vs_transaction.py`
  (`results_batch_vs_transaction/`) measured 500 Observations at 8.3-9.0 s
  as a batch and 1.5-1.8 s as a transaction on a fresh file store, which
  is what run c changed. In run c each 500 still took ~6 s; run d put the
  500 pair writes in one commit (the store syncs each commit to disk).
- Memory: each server stayed 1.48-1.67 GB (the idle JIT process is 1.59
  GB) at 10,000.
- 200 resources (`results_200/`, run a's code): 10.8 s, 1.2 s, 3.5 s.

## The whole MIMIC-IV store: 928,935 resources

`KEEP_A=1 run.sh 1000000`: A loaded once (38 min, `perf_load.dart`), kept
for each run; B started empty each time. Run e's code first, then one
change a row.

| run | code | first sync | nothing changed | 100 changed |
|---|---|---|---|---|
| f | run e | stopped | | |
| g | history pages read from two order indexes (fhirant_db schema 30) | 7,431 s | 1,411 s | 3.7 s |
| h | the next page found from where the last ended (`_cursor`), not by offset | 6,091 s | 155 s | 3.5 s |

All 928,935 written in each first sync, no failures; one run of each.

- Run f (`results_full_before_index/`): each 500-version page of system
  history took 3.9-5.7 s on A, rising with depth, because every page
  sorted every version the store holds. Stopped after 108 of ~1,860
  pages. `history_keyed.dart` (`results_history_keyed.txt`) times the
  index-ordered page at 33-264 ms against 3.9-5.7 s, the same rows at
  five depths. 2,786 groups of versions shared a millisecond and a version
  id, so the order now also breaks ties by type and id.
- Run g (`results_full_g_order_index/`): the first sync was B's writes,
  ~3 s for each 500 (1.65 s at the start, A's page 112-261 ms). A sync
  with nothing changed made one request to A and spent 1,411 s paging
  B's own history: the first sync's 928,935 copies and the 934,798
  AuditEvents of those writes (1,863,732 versions; B's file 11.9 GB, A's
  6.4 GB), each found unchanged. Each page was found by `OFFSET`;
  `history_keyset.dart` (`results_history_keyset.txt`) on B's store: 395
  ms at depth 1.87 million by offset, 1 ms by position, the same rows.
- Run h (`results_full_h_keyset/`): the `next` link carries the last
  row's position (R4B http.html §3.1.0.14: "A server MAY add additional
  state tracking parameters to the links"), and the total is given on the
  first page only. B still pages its own writes in a sync after a first
  sync; 155 s is that cost now.
- Memory: peak 1.63 GB (A) and 1.90 GB (B) in run h, 1.64 and 1.86 in g.
