# Bytes per table and index, from SQLite's dbstat virtual table, read on a
# copy-free read-only connection.
import sqlite3, sys
c = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
out = open(sys.argv[2], 'w')
rows = c.execute("""select s.name, m.tbl_name, m.type, sum(s.pgsize)
  from dbstat s left join sqlite_master m on m.name = s.name
  group by s.name order by 4 desc""").fetchall()
tot = sum(r[3] for r in rows)
out.write('name\ttable\tkind\tbytes\tshare\n')
for n, t, k, b in rows:
    out.write(f'{n}\t{t}\t{k}\t{b}\t{b/tot:.3f}\n'); out.flush()
out.write(f'TOTAL\t\t\t{tot}\t1\n')
for t in ['resources', 'resources_history']:
    try:
        n, s = c.execute(f'select count(*), sum(length(resource)) from {t}').fetchone()
        out.write(f'rows:{t}\t{n}\tjson_bytes\t{s}\n')
    except Exception as e:
        out.write(f'rows:{t}\terror\t{e}\n')
