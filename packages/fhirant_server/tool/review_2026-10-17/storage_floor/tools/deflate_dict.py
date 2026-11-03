# Per-resource deflate with a preset dictionary (zlib zdict; Dart's
# ZLibEncoder(dictionary:) is the same). Dictionary per file: the last 32 KiB
# of the first 200 resources (deflate's window is 32 KiB). Measured on the
# rest of the file, so no resource is compressed against itself.
import sys, os, zlib
d = sys.argv[1]; out = open(sys.argv[2], 'w')
out.write('file\tcount\traw_bytes\tdict_bytes\tratio\n'); R = C = 0
for f in sorted(os.listdir(d)):
    if not f.endswith('.ndjson'): continue
    lines = [l.rstrip(b'\n') for l in open(os.path.join(d, f), 'rb') if l.strip()]
    zd = b''.join(lines[:200])[-32768:]
    rest = lines[200:] or lines
    r = c = 0
    for l in rest:
        co = zlib.compressobj(6, zlib.DEFLATED, 15, 8, zlib.Z_DEFAULT_STRATEGY, zd)
        b = co.compress(l) + co.flush()
        do = zlib.decompressobj(15, zd); assert do.decompress(b) == l
        r += len(l); c += len(b)
    R += r; C += c
    out.write(f'{f}\t{len(rest)}\t{r}\t{c}\t{r/c:.2f}\n'); out.flush()
out.write(f'ALL\t\t{R}\t{C}\t{R/C:.2f}\n')
