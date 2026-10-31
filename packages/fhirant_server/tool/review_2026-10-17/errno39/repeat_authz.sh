#!/usr/bin/env bash
# Runs system_operation_authz_test.dart N times, each with the export-job
# group's tests, and records pass/fail and any errno 39 per run, flushed per
# line, to repeat_authz.tsv. Arg 2 "load" runs 12 busy loops alongside, as the
# full suite's other isolates load the machine.
# Run from packages/fhirant_server: tool/review_2026-10-17/errno39/repeat_authz.sh <runs> [load]
set -u
OUT=tool/review_2026-10-17/errno39/repeat_authz.tsv
LOGS=/tmp/claude-1000/errno39_runs; mkdir -p "$LOGS"
printf 'run\tload\texit\terrno39\n' > "$OUT"
PIDS=()
if [ "${2:-}" = load ]; then
  for _ in $(seq 12); do (exec yes > /dev/null) & PIDS+=($!); done
fi
for i in $(seq "$1"); do
  dart test test/integration/system_operation_authz_test.dart > "$LOGS/$i.log" 2>&1
  code=$?
  n=$(grep -c "errno = 39" "$LOGS/$i.log")
  printf '%s\t%s\t%s\t%s\n' "$i" "${2:-none}" "$code" "$n" >> "$OUT"
done
for p in "${PIDS[@]}"; do kill "$p"; done
