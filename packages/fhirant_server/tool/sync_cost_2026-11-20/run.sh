#!/usr/bin/env bash
# Measures what one $sync costs: server A holds N MIMIC resources, server B
# is empty, and B runs $sync with A as its peer (a new device pulling a
# store). Then a second $sync with nothing changed, then one after 100
# changes on A. Both servers are the CLI in dev mode on this machine.
#
# Usage: tool/sync_cost_2026-11-20/run.sh N
# KEEP_A=1 keeps server A's store from an earlier run of the same N (the
# load of all 929,047 took 38 min) and starts everything else afresh.
# Output: .dart_tool/sync_cost/N/{progress.tsv,results.tsv,a.log,b.log}
# progress.tsv gets a row every 10 s (flushed): elapsed seconds, requests A
# has logged (resource routes), RSS of A and B in MB.
set -u
N=$1
HERE=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$HERE/.dart_tool/sync_cost/$N
MIMIC=/home/grey/Downloads/mimic-iv-clinical-database-demo-on-fhir-2.1.0/fhir
export TMPDIR=$HERE/.dart_tool/tmp
mkdir -p "$TMPDIR"
cd "$HERE"
PA=18181; PB=18182
if [ "${KEEP_A:-}" = 1 ] && [ -f "$OUT/a/fhirant.db" ]; then
  find "$OUT" -mindepth 1 -maxdepth 1 ! -name a -exec rm -rf {} +
  mkdir -p "$OUT/b"
  echo "load kept $(date -Is)" >> "$OUT/results.tsv"
else
  rm -rf "$OUT"; mkdir -p "$OUT/a" "$OUT/b"
  echo "load start $(date -Is)" >> "$OUT/results.tsv"
  dart run tool/perf_load.dart "$MIMIC" "$OUT/a" --limit "$N" --batch 500 \
    --server-store > "$OUT/load.log" 2>&1
  echo "load exit $? $(date -Is)" >> "$OUT/results.tsv"
fi

start_server() { # port dir log
  (exec dart run bin/server.dart --dev-mode --port "$1" --db-path "$2" \
    --spec-path "$OUT/no-spec" > "$3" 2>&1) &
  echo $!
}
APID=$(start_server $PA "$OUT/a" "$OUT/a.log")
for i in $(seq 1 120); do curl -sf localhost:$PA/health >/dev/null && break; sleep 1; done
BPID=$(start_server $PB "$OUT/b" "$OUT/b.log")
for i in $(seq 1 120); do curl -sf localhost:$PB/health >/dev/null && break; sleep 1; done
echo -e "pids\t$APID\t$BPID" >> "$OUT/results.tsv"
trap 'kill $APID $BPID 2>/dev/null' EXIT

rss() { awk '/VmRSS/{printf "%.0f", $2/1024}' /proc/$1/status 2>/dev/null; }
count() { curl -s "localhost:$1/$2?_summary=count" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("total"))' 2>/dev/null; }

sync_once() { # label
  local t0=$(date +%s.%N)
  curl -s -o /dev/null -w '%{http_code}' -X POST "localhost:$PB/\$sync" \
    -H 'content-type: application/fhir+json' \
    -d "{\"resourceType\":\"Parameters\",\"parameter\":[{\"name\":\"peer\",\"valueString\":\"http://localhost:$PA\"}]}" \
    > "$OUT/kick_$1.code"
  while :; do
    local code
    code=$(curl -s -o "$OUT/status_$1.json" -w '%{http_code}' "localhost:$PB/\$sync-status")
    local el
    el=$(python3 -c "print(round($(date +%s.%N)-$t0,1))")
    echo -e "$1\t$el\t$(grep -cE '"message":"(GET|PUT|DELETE|POST) /[A-Z]' "$OUT/a.log")\t$(rss $APID)\t$(rss $BPID)\t$code" >> "$OUT/progress.tsv"
    [ "$code" != 202 ] && break
    sleep 10
  done
  echo -e "sync\t$1\t$(python3 -c "print(round($(date +%s.%N)-$t0,1))")\t$(cat "$OUT/kick_$1.code")" >> "$OUT/results.tsv"
}

echo -e "label\tseconds\ta_log_lines\ta_rss_mb\tb_rss_mb\tstatus" > "$OUT/progress.tsv"
sync_once first
echo -e "counts\tA_Patient\t$(count $PA Patient)\tB_Patient\t$(count $PB Patient)" >> "$OUT/results.tsv"
sync_once unchanged
# 100 changes on A: Patient resources get a new gender-free extension-free
# field (birthDate kept), via PUT.
python3 - "$PA" > "$OUT/changes.log" 2>&1 <<'PY'
import json, sys, urllib.request
port = sys.argv[1]
b = json.load(urllib.request.urlopen(f"http://localhost:{port}/Patient?_count=100"))
n = 0
for e in b.get("entry", []):
    r = e["resource"]; r["active"] = not r.get("active", False)
    req = urllib.request.Request(f"http://localhost:{port}/Patient/{r['id']}",
        data=json.dumps(r).encode(), method="PUT",
        headers={"content-type": "application/fhir+json"})
    urllib.request.urlopen(req).read(); n += 1
print("changed", n, flush=True)
PY
sync_once hundred
echo "done $(date -Is)" >> "$OUT/results.tsv"
