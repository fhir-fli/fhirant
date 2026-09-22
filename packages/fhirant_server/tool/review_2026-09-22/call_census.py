#!/usr/bin/env python3
"""Which calls are made from many handler files?

A decision repeated across handlers shows up as the same call at many
sites, whatever the surrounding wording. The five-line-block census
(tool/duplication) misses exactly that: it needs identical text.

Writes one TSV row per call name: files, sites.
"""
import collections
import pathlib
import re
import sys

CALL = re.compile(r"\b([A-Za-z_][\w.]*)\(")
NOISE = {'if', 'for', 'while', 'switch', 'catch', 'return', 'print', 'expect',
         'test', 'group', 'super', 'async', 'await', 'Future', 'Map', 'List',
         'Set', 'String', 'int', 'Duration', 'DateTime', 'Uri', 'Response',
         'Request', 'Exception', 'StateError', 'FormatException',
         'ArgumentError', 'Object', 'const', 'assert', 'Text', 'Icon'}

def main(root, out_path):
    files = collections.defaultdict(set)
    sites = collections.Counter()
    for f in sorted(pathlib.Path(root).rglob('*.dart')):
        for line in f.read_text().splitlines():
            s = line.strip()
            if s.startswith('//'):
                continue
            for m in CALL.finditer(s):
                name = m.group(1)
                if name.split('.')[-1] in NOISE or name.split('.')[0] in NOISE:
                    continue
                files[name].add(str(f))
                sites[name] += 1
    out = pathlib.Path(out_path)
    with out.open('w') as fh:
        fh.write('call\tfiles\tsites\n')
        for name, fs in sorted(files.items(), key=lambda kv: (-len(kv[1]), -sites[kv[0]])):
            fh.write(f'{name}\t{len(fs)}\t{sites[name]}\n'); fh.flush()
    print(f'{len(files)} distinct calls', flush=True)

if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
