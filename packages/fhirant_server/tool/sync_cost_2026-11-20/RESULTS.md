# What one `$sync` costs, measured 2026-11-20

`run.sh N`: server A (CLI, dev mode) holds N MIMIC-IV resources loaded by
`perf_load.dart --server-store`; server B is empty and runs `$sync` with A as
its peer. Times are the job's own `started`/`finished` (status_*.json).

| N | sync | considered | written to A | written to B | seconds |
|---|---|---|---|---|---|
| 200 | first | 200 | 200 | 200 | 10.8 |
| 200 | nothing changed | 200 | 0 | 0 | 1.2 |
| 200 | 100 changed on A | 100 | 0 | 100 | 3.5 |
| 10,000 | first | 10,000 | 10,000 | 10,000 | 1,227 |
| 10,000 | nothing changed | 10,000 | 0 | 0 | 620 |
| 10,000 | 100 changed on A | 100 | 0 | 100 | 6.5 |

- The first sync writes every resource back to A: B adds `meta.source`
  (A's URL) to a copy that had none, the merge is then different from A's
  version, so it is PUT to A. A gains a version of every resource, and the
  next sync with nothing changed by anyone reads all 10,000 again.
- At 10,000 the run is held by A's rate limit (dev mode 1,000 requests a
  minute from one address; 600 outside dev mode): 20,128 requests to A in
  the first 1,207 s. Two per resource: its history, and the write-back.
- Memory: each server stayed 1.48-1.67 GB (the idle JIT process is 1.59
  GB); no growth with N was seen.
- Not run: the 929k store. Derived from the 10,000 rate, not measured:
  ~32 h for a first sync at 1,000 a minute, ~52 h at 600, and half that
  again for the next sync.

Since measured: the sync no longer adds `meta.source` (R4B resource.html,
Meta.source: "the server SHOULD generally leave this unchanged"), so the
write-back and the re-read after it are gone. Not yet re-measured.
