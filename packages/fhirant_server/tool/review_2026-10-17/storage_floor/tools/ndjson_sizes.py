import sys, os, statistics
d = sys.argv[1]; out = open(sys.argv[2], 'w')
out.write('file\tcount\tmean_bytes\tmedian\n'); tot = n = 0
for f in sorted(os.listdir(d)):
    if not f.endswith('.ndjson'): continue
    v = [len(l.rstrip(b'\n')) for l in open(os.path.join(d, f), 'rb') if l.strip()]
    tot += sum(v); n += len(v)
    out.write(f'{f}\t{len(v)}\t{statistics.mean(v):.0f}\t{statistics.median(v):.0f}\n'); out.flush()
out.write(f'ALL\t{n}\t{tot/n:.0f}\ttotal_bytes={tot}\n')
