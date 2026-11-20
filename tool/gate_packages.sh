#!/bin/bash
# Format, analyze and test fhirant_server, fhirant_db and the app, the way
# CI does, one line per step to $OUT/gate.log (default .dart_tool/gate).
# Test temp files go under the package's .dart_tool: /tmp (tmpfs) ran out
# of quota twice in a full server run on 2026-11-19.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/.dart_tool/gate}
mkdir -p "$OUT" "$ROOT/packages/fhirant_server/.dart_tool/tmp"
L=$OUT/gate.log; : > "$L"
export TMPDIR=$ROOT/packages/fhirant_server/.dart_tool/tmp
fail=0
step() { echo "$*" >> "$L"; [ "$3" = 0 ] || fail=1; }
for p in fhirant_server fhirant_db; do
  cd "$ROOT/packages/$p" || exit 1
  dart format --output=none --set-exit-if-changed . > "$OUT/fmt_$p.log" 2>&1; step "$p" fmt $?
  dart analyze > "$OUT/analyze_$p.log" 2>&1; step "$p" analyze $?
  timeout 2400 dart test > "$OUT/test_$p.log" 2>&1; step "$p" test $? "$(tail -1 "$OUT/test_$p.log")"
done
cd "$ROOT/packages/fhirant" || exit 1
dart format --output=none --set-exit-if-changed . > "$OUT/fmt_app.log" 2>&1; step app fmt $?
flutter analyze > "$OUT/analyze_app.log" 2>&1; step app analyze $?
timeout 1200 flutter test > "$OUT/test_app.log" 2>&1; step app test $? "$(tail -1 "$OUT/test_app.log")"
echo "DONE $fail" >> "$L"
exit $fail
