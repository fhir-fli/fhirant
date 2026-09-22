#!/usr/bin/env python3
"""Count repeated code blocks in Dart source, per package.

A block is 5 consecutive non-comment, non-blank lines, whitespace-normalised
and at least 80 characters long. A block counts as repeated when it appears
3 or more times. Generated code is skipped: it is written by a generator, so
repetition there is not a hand-written duplication.

Writes one TSV row per package as it goes.
"""
import collections
import pathlib
import re
import sys

# Generated code and data tables, found by reading the top repeated block of
# every package on 2026-09-22: cicada's generated_files (CDC data), the
# generator's fhir_field_map.dart and at_rest search_*.dart (a header says
# auto-generated), the db search tables, cql's model-info files, ucum's
# defined units.
SKIP = ('/test/', '/build/', '.g.dart', '/generated/', '/generated_files/',
        'search_parameters.dart', 'search_parameter_types.dart',
        'fhir_field_map.dart', '/searches/search_', '/model_info/', '/antlr/',
        'defined_units.dart', '/resource_types/', '/data_types/',
        '/primitive_types/')


def census(root: pathlib.Path):
    blocks = collections.defaultdict(list)
    files = 0
    for path in root.rglob('*.dart'):
        s = str(path)
        if any(k in s for k in SKIP):
            continue
        files += 1
        lines = [re.sub(r'\s+', ' ', l.strip()) for l in
                 path.read_text(errors='replace').splitlines()]
        lines = [l for l in lines if l and not l.startswith(('//', '///'))]
        for i in range(len(lines) - 4):
            key = '\n'.join(lines[i:i + 5])
            if len(key) < 80:
                continue
            blocks[key].append(f'{path}:{i + 1}')
    dups = {k: v for k, v in blocks.items() if len(v) >= 3}
    return files, len(dups), sum(len(v) for v in dups.values()), dups


def main(argv):
    out = pathlib.Path(argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    fh = out.open('w')
    fh.write('package\tfiles\trepeated_blocks\tsites\ttop_copies\ttop_first_line\n')
    fh.flush()
    for root in argv[2:]:
        p = pathlib.Path(root)
        files, nblocks, sites, dups = census(p)
        top = max(dups.items(), key=lambda kv: len(kv[1]), default=(None, []))
        first = top[0].splitlines()[0][:60] if top[0] else ''
        fh.write(f'{p}\t{files}\t{nblocks}\t{sites}\t{len(top[1])}\t{first}\n')
        fh.flush()
        print(f'{p}: {files} files, {nblocks} repeated blocks, {sites} sites',
              flush=True)
    fh.close()


if __name__ == '__main__':
    sys.exit(main(sys.argv))
