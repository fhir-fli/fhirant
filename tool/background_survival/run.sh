#!/usr/bin/env bash
# Does the fhirant app keep serving when it is not on screen?
#
# Polls GET /health over Wi-Fi every 10 s from this machine, so it keeps
# measuring with the USB cable out. One TSV line per poll, flushed as it is
# written. The health body's `uptime` resets if the server restarts, so a
# silent restart shows as uptime going down, not as a gap.
#
#   run.sh poll <label> <minutes> <https://phone-ip:port>
#   run.sh state          # pid and process state (needs adb)
#   run.sh home           # send the app off screen (needs adb)
#   run.sh why            # why the app last died: ApplicationExitInfo
#
# Method copied from sensorium's Phase 16 (graiai/sensorium/PLAN.md).
set -u
PKG=dev.fhirfli.fhirant.app
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/runs"
mkdir -p "$OUT_DIR"
step=${1:-}
case "$step" in
  poll)
    label=$2; minutes=$3; base=$4
    out="$OUT_DIR/$(date +%Y%m%d-%H%M%S)_$label.tsv"
    printf 'time\thttp\tseconds\tuptime\n' > "$out"
    end=$(( $(date +%s) + minutes * 60 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      t=$(date +%H:%M:%S)
      body=$(curl -sk -m 8 -o - -w '\n%{http_code}\t%{time_total}' "$base/health" 2>/dev/null)
      code_time=$(printf '%s' "$body" | tail -n1)
      up=$(printf '%s' "$body" | head -n -1 | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("uptime",""))
except Exception: print("")')
      printf '%s\t%s\t%s\n' "$t" "$code_time" "$up" >> "$out"
      echo "$t $code_time uptime=$up"
      sleep 10
    done
    echo "wrote $out"
    ;;
  state)
    pid=$(adb shell pidof "$PKG" | tr -d '\r')
    echo "pid=${pid:-none}"
    adb shell dumpsys activity processes "$PKG" | grep -m3 -oE 'procState=\S+|curProcState=\S+|mCurProcState=\S+|fgServices=\S+|hasForegroundServices=\S+'
    ;;
  home)
    adb shell input keyevent KEYCODE_HOME
    echo "home sent $(date +%H:%M:%S)"
    ;;
  why)
    adb shell dumpsys activity exit-info "$PKG" | grep -E 'timestamp=|reason=|description=|importance=' | head -n 12
    ;;
  *) echo "usage: run.sh poll|state|home|why ..."; exit 2 ;;
esac
