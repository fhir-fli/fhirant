import sys, collections
out = open(sys.argv[1], 'w')
runs = sys.argv[2:]
data = {}
for p in runs:
    agg = collections.OrderedDict()
    for l in open(p):
        f = l.rstrip('\n').split('\t')
        if f[0] != 'load': continue
        a = agg.setdefault(f[1], [0, 0.0]); a[0] += int(f[2]); a[1] += float(f[3])
    data[p] = agg
files = list(next(iter(data.values())).keys())
out.write('file\t' + '\t'.join(r.split('/')[-2] + '_per_s' for r in runs) + '\n')
for fl in files:
    out.write(fl + '\t' + '\t'.join(f"{data[r][fl][0]/data[r][fl][1]:.0f}" if fl in data[r] and data[r][fl][1] else '-' for r in runs) + '\n')
for r in runs:
    n = sum(v[0] for v in data[r].values()); s = sum(v[1] for v in data[r].values())
    out.write(f'TOTAL {r}\t{n}\t{s:.0f}s\t{n/s:.0f}/s\n')
out.flush()
