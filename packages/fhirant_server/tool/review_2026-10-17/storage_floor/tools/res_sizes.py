import json, sys, collections, statistics
b = json.load(open(sys.argv[1]))
out = open(sys.argv[2], 'w')
by = collections.defaultdict(list)
for e in b['entry']:
    r = e['resource']
    n = len(json.dumps(r, separators=(',', ':')).encode())
    by[r['resourceType']].append(n)
allv = [n for v in by.values() for n in v]
out.write('type\tcount\tmean_bytes\tmedian\tmax\n')
for t, v in sorted(by.items(), key=lambda x: -len(x[1])):
    out.write(f'{t}\t{len(v)}\t{statistics.mean(v):.0f}\t{statistics.median(v):.0f}\t{max(v)}\n'); out.flush()
out.write(f'ALL\t{len(allv)}\t{statistics.mean(allv):.0f}\t{statistics.median(allv):.0f}\t{max(allv)}\n')
encs = len(by.get('Encounter', []))
out.write(f'encounters\t{encs}\tresources_per_encounter\t{len(allv)/encs if encs else 0:.2f}\n')
