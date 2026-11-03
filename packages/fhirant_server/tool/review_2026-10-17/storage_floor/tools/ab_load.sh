#!/bin/bash
# A/B the save path: September 6 (fhirant 852d697 + fhir_r4_db d13f2838f)
# against today's main, the same 100,000 chart observations into an empty
# database, interleaved so machine load hits both alike.
SUB=/tmp/claude-1000/dbsize/sub100k
OUT=/tmp/claude-1000/dbsize/ab
SEP=/tmp/claude-1000/ab_sep/packages/fhirant_server
NOW=/home/grey/dev/fhir/fhirant/packages/fhirant_server
[ -f $OUT/summary.tsv ] || echo -e "round\tbuild\tseconds\texit" > $OUT/summary.tsv
for round in ${ROUNDS:-1 2}; do
  for build in ${ORDER:-sep now}; do
    dir=$SEP; [ $build = now ] && dir=$NOW
    db=$OUT/${build}_$round; rm -rf $db; mkdir -p $db
    start=$(date +%s.%N)
    (cd $dir && exec /usr/bin/time -o $OUT/${build}_$round.time -f "%e wall %U user %S sys" dart run tool/perf_load.dart $SUB $db --batch 500) > $OUT/${build}_$round.log 2>&1
    rc=$?
    end=$(date +%s.%N)
    echo -e "$round\t$build\t$(echo "$end - $start" | bc)\t$rc" >> $OUT/summary.tsv
    grep "total-load" $OUT/${build}_$round.log >> $OUT/summary.tsv
    rm -rf $db/fhirant.sqlite*
  done
done
echo done >> $OUT/summary.tsv
