#!/usr/bin/env python3
"""Mutation check of the $sync tests: each mutant breaks one rule; a test
must fail on it. Writes mutants.tsv beside this script, one row per mutant,
flushed as it goes. Run from packages/fhirant_server."""
import pathlib, subprocess, sys

HERE = pathlib.Path(__file__).parent
TESTS = ['test/sync/merge_test.dart', 'test/integration/server_sync_test.dart']
MUTANTS = [
    ('field time is the latest save, not the save that set it',
     'lib/src/sync/merge.dart',
     '  return side.since[start].lastUpdated;\n}',
     '  return current.lastUpdated;\n}'),
    ('the older save wins a field both sides changed',
     'lib/src/sync/merge.dart',
     'final localWins = lAt.isAfter(rAt!);',
     'final localWins = !lAt.isAfter(rAt!);'),
    ('neither side changed, different values: take local',
     'lib/src/sync/merge.dart',
     '    } else if (lAt == null) {\n      value = rv;',
     '    } else if (lAt == null && rAt != null) {\n      value = rv;\n    } else if (lAt == null) {\n      value = lv;'),
    ('a delete always wins',
     'lib/src/sync/merge.dart',
     '  return changedAt.isAfter(gone.lastUpdated)',
     '  return false'),
    ('the base is ignored',
     'lib/src/sync/sync_job.dart',
     '    if (baseVersion == null) return SyncSide(since: versions);',
     '    return SyncSide(since: versions);'),
    ('the cursor moves even when a write failed',
     'lib/src/sync/sync_job.dart',
     '    if (report.failures.isEmpty) {\n      await db.setSyncCursor(',
     '    if (true) {\n      await db.setSyncCursor('),
    ('audit events are synced',
     'lib/src/sync/sync_job.dart',
     "const syncSkippedTypes = {'AuditEvent', 'Subscription'};",
     "const syncSkippedTypes = {'Subscription'};"),
    ('a 412 on the peer is ignored and the pair recorded',
     'lib/src/sync/sync_job.dart',
     "      report.retryLater.add('$key (changed $where during the sync)');\n      return null;\n    }\n    if (written.status >= 300) {",
     "      report.retryLater.add('$key (changed $where during the sync)');\n      return (versionId: current?.versionId);\n    }\n    if (written.status >= 300) {"),
    # Review of PR #110, 2026-11-19: one mutant per fix.
    ('a peer key is not checked',
     'lib/src/sync/sync_endpoint.dart',
     '    if (R4ResourceType.fromString(type) == null ||\n        !fhirIdGrammar.hasMatch(id)) {',
     '    if (false) {'),
    ('the local side skips the audit and scope check',
     'lib/src/fhirant_server.dart',
     '          router: () => syncLocalHandler(_router.call),',
     '          router: () => _router.call,'),
    ('meta.extension is dropped',
     'lib/src/sync/merge.dart',
     "      if (part is String && !serverMetaFields.contains(part)) {",
     "      if (part is String && const {'source', 'profile', 'security', 'tag'}.contains(part)) {"),
    ('history ordered by time',
     'lib/src/sync/sync_endpoint.dart',
     '    return byVersion.values.toList().reversed.toList();',
     '    return byVersion.values.toList()..sort((a, b) => a.lastUpdated.compareTo(b.lastUpdated));'),
    ('a clock set back is not noticed',
     'lib/src/sync/sync_job.dart',
     '    return side.changedSince(null);\n  }',
     '    return found;\n  }'),
    ('a peer URL may carry credentials',
     'lib/src/handlers/sync_handler.dart',
     '  if (peer.userInfo.isNotEmpty) {',
     '  if (false) {'),
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
