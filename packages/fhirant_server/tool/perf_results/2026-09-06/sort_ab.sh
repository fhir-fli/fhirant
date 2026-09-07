#!/bin/bash
# A/B of the sort-index walk on the loaded MIMIC database: the same build, the
# same database, one variable, interleaved twice. Each run writes its own file
# as it goes (perf_search prints per query).
S=/tmp/claude-1000/-home-grey-dev-fhir/de68eaae-3b41-4d09-83f0-1afc69eb2c0c/scratchpad
cd /home/grey/dev/fhir/fhirant/packages/fhirant_server || exit 1
for round in 1 2; do
  for arm in walk nowalk; do
    flag=""; [ "$arm" = nowalk ] && flag="--no-sort-walk"
    echo "== round $round arm $arm $(date +%T)"
    dart run tool/perf_search.dart "$S/perffull" --skip-chains $flag > "$S/sort_ab_${arm}_$round.txt" 2>&1
    grep "^sort" "$S/sort_ab_${arm}_$round.txt"
  done
done
