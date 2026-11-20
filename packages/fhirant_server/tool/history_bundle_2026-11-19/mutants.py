#!/usr/bin/env python3
"""Mutation check of the history-Bundle tests: each mutant breaks one rule;
a test must fail on it. Writes mutants.tsv beside this script, one row per
mutant, flushed as it goes. Run from packages/fhirant_server."""
import pathlib, subprocess

HERE = pathlib.Path(__file__).parent
TESTS = ['test/integration/history_bundle_test.dart']
B = 'lib/src/handlers/bundle_handler.dart'
MUTANTS = [
    ('newest version applied first', B,
     'List<int>.generate(bundle.entry!.length, (i) => i).reversed.toList()',
     'List<int>.generate(bundle.entry!.length, (i) => i)'),
    ('a repeated resource is refused as in a transaction', B,
     'if (identity != null && !history) {',
     'if (identity != null) {'),
    ('response.location is not checked', B,
     '      if (named != key) {',
     '      if (false) {'),
    ('a DELETE need not name an id', B,
     "      if (parts.length != 2 || !fhirIdGrammar.hasMatch(parts[1])) {",
     "      if (parts.isEmpty) {"),
    ('a resource without an id is accepted', B,
     '    if (resource == null || id == null) {',
     '    if (resource == null) {'),
    ('history create entries carry no Location', 'lib/src/handlers/history_handler.dart',
     "      location: isCreate && !e.deleted",
     "      location: false"),
]

out = (HERE / 'mutants.tsv').open('w')
out.write('mutant\tcaught\tfailing tests\n'); out.flush()
for name, path, old, new in MUTANTS:
    p = pathlib.Path(path)
    source = p.read_text()
    if source.count(old) != 1:
        out.write(f'{name}\tNOT APPLIED (pattern found {source.count(old)} times)\t\n'); out.flush()
        continue
    p.write_text(source.replace(old, new))
    try:
        run = subprocess.run(['dart', 'test', *TESTS], capture_output=True, text=True, timeout=900)
    finally:
        p.write_text(source)
    failed = sorted({l.split(': ', 1)[1].replace(' [E]', '').strip()
                     for l in run.stdout.splitlines() if l.endswith('[E]')})
    caught = run.returncode != 0
    out.write(f"{name}\t{'yes' if caught else 'NO'}\t{'; '.join(failed)}\n"); out.flush()
    print(name, 'caught' if caught else 'SURVIVED', flush=True)
