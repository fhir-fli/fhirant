#!/bin/bash
# Full MIMIC load with the covering value indexes skipped (FHIR_DB_NARROW=2,
# owner indexes kept for the delete), then the covers built once at the end.
OUT=/tmp/claude-1000/dbsize/load_then_index; mkdir -p $OUT; rm -rf $OUT/db; mkdir $OUT/db
DIR=/tmp/claude-1000/ab_now/packages/fhirant_server
MIMIC=/home/grey/Downloads/mimic-iv-clinical-database-demo-on-fhir-2.1.0/fhir
(cd $DIR && FHIR_DB_NARROW=2 exec /usr/bin/time -o $OUT/load.time -f "%e\t%U\t%S" dart run tool/perf_load.dart $MIMIC $OUT/db --batch 500) > $OUT/load.log 2>&1
echo "load rc=$? $(cat $OUT/load.time)" > $OUT/summary.txt
grep "total-load\|database size" $OUT/load.log >> $OUT/summary.txt
(cd $DIR && FHIR_DB_NARROW=0 exec /usr/bin/time -o $OUT/index.time -f "%e\t%U\t%S" dart run tool/scratch_build_indexes.dart $OUT/db) > $OUT/index.log 2>&1
echo "index rc=$? $(cat $OUT/index.time)" >> $OUT/summary.txt
cat $OUT/index.log >> $OUT/summary.txt
python3 -I -c "
import sqlite3; c=sqlite3.connect('file:$OUT/db/fhirant.sqlite?mode=ro',uri=True)
print('cover indexes', c.execute(\"select count(*) from sqlite_master where name like '%_cover'\").fetchone()[0])" >> $OUT/summary.txt
ls -la $OUT/db >> $OUT/summary.txt
echo done >> $OUT/summary.txt
