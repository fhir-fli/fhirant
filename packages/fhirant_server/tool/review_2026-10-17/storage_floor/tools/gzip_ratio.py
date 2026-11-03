import sys, os, zlib
d = sys.argv[1]; out = open(sys.argv[2], 'w')
out.write('file\tcount\traw_bytes\tdeflate6_bytes\tratio\n'); R = C = 0
for f in sorted(os.listdir(d)):
    if not f.endswith('.ndjson'): continue
    r = c = n = 0
    for l in open(os.path.join(d, f), 'rb'):
        l = l.rstrip(b'\n')
        if not l: continue
        n += 1; r += len(l); c += len(zlib.compress(l, 6))
    R += r; C += c
    out.write(f'{f}\t{n}\t{r}\t{c}\t{r/c:.2f}\n'); out.flush()
out.write(f'ALL\t\t{R}\t{C}\t{R/C:.2f}\n')
