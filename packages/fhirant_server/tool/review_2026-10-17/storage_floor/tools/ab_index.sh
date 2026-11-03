#!/bin/bash
# One variable: today's code (fhirant main + fhir_db 0.15.2 copy) with the
# covering value indexes (base) against the September single-column ones
# (narrow), 20,000 chart observations into an empty database, interleaved.
SUB=/tmp/claude-1000/dbsize/sub20k
OUT=/tmp/claude-1000/dbsize/ab_index; mkdir -p $OUT
DIR=/tmp/claude-1000/ab_now/packages/fhirant_server
echo -e "round\tvariant\twall\tuser\tsys\tload_line" > $OUT/summary.tsv
for round in 1 2 3; do
  for v in base narrow; do
    db=$OUT/${v}_$round; rm -rf $db; mkdir -p $db
    n=0; [ $v = narrow ] && n=1
    (cd $DIR && FHIR_DB_NARROW=$n exec /usr/bin/time -o $OUT/${v}_$round.time -f "%e\t%U\t%S" dart run tool/perf_load.dart $SUB $db --batch 500) > $OUT/${v}_$round.log 2>&1
    python3 -I -c "
import sqlite3; c=sqlite3.connect('file:$db/fhirant.sqlite?mode=ro',uri=True)
print('\n'.join(r[0] for r in c.execute(\"select name from sqlite_master where type='index' and name like 'idx_%' order by 1\")))" > $OUT/${v}_$round.indexes
    echo -e "$round\t$v\t$(cat $OUT/${v}_$round.time)\t$(grep total-load $OUT/${v}_$round.log)" >> $OUT/summary.tsv
    rm -f $db/fhirant.sqlite*
  done
done
echo done >> $OUT/summary.tsv
