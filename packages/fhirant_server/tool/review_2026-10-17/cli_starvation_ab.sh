#!/usr/bin/env bash
# Runs cli_starvation_check.dart against one CLI build: starts
# bin/server.dart from <tree> in --dev-mode on a fresh store, polls <path>
# during five 2,000-entry Bundles, idles 60 s, stops the server by its pid
# and records how long the stop took and what it logged.
#
# Usage, from packages/fhirant_server of the tree being measured from:
#   tool/review_2026-10-17/cli_starvation_ab.sh <label> <tree> <port> <path>
# <tree> is a fhirant checkout (a worktree at the commit to compare).
set -euo pipefail
label=$1 tree=$2 port=$3 path=$4
here=$(pwd)
work=/tmp/claude-1000/cli_check/$label
rm -rf "$work" && mkdir -p "$work"
(cd "$tree/packages/fhirant_server" &&
  exec dart run bin/server.dart --dev-mode --port "$port" \
    --db-path "$work/db" >"$work/server.log" 2>&1) &
pid=$!
echo "server pid $pid" >>"$work/run.txt"
for _ in $(seq 1 120); do
  if curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/health" |
    grep -q 200; then break; fi
  sleep 1
done
uptime >>"$work/run.txt"
dart run tool/review_2026-10-17/cli_starvation_check.dart \
  "$label" "http://localhost:$port" "$path" 5 >>"$work/run.txt" 2>&1
sleep 60
uptime >>"$work/run.txt"
start=$(date +%s%N)
kill "$pid"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
echo "stop_ms $(( ($(date +%s%N) - start) / 1000000 ))" >>"$work/run.txt"
grep -E 'SIGTERM|still queued|Server stopped' "$work/server.log" \
  >>"$work/run.txt" || true
cd "$here"
cat "$work/run.txt"
