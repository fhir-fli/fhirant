#!/usr/bin/env bash
# Does an $export job still sometimes never finish (PLAN.md, "An export job
# occasionally never finishes": 1 in 8 whole-suite runs, 2026-08-30)? Runs
# export_integration_test.dart N times beside 12 busy loops, as
# errno39/repeat_authz.sh does, and records per run the exit code and whether
# pollUntilComplete's deadline message appeared, one line flushed per run.
# Run from packages/fhirant_server:
#   tool/review_2026-10-17/export_stall/repeat_export.sh <runs>
set -u
OUT=${OUT:-tool/review_2026-10-17/export_stall/repeat_export.tsv}
LOGS=/tmp/claude-1000/export_stall_runs; mkdir -p "$LOGS"
printf 'run\texit\tpassed\tdeadline_msgs\n' > "$OUT"
PIDS=()
for _ in $(seq 12); do (exec yes > /dev/null) & PIDS+=($!); done
for i in $(seq "$1"); do
  dart test test/integration/export_integration_test.dart > "$LOGS/$i.log" 2>&1
  code=$?
  passed=$(grep -o '+[0-9]*' "$LOGS/$i.log" | tail -n 1)
  n=$(grep -c 'did not finish within\|is gone: the status\|TimeoutException' "$LOGS/$i.log")
  printf '%s\t%s\t%s\t%s\n' "$i" "$code" "$passed" "$n" >> "$OUT"
done
for p in "${PIDS[@]}"; do kill "$p"; done
