"""Which content types do FHIR attachments carry, in the published examples?

For fhirant's file-type check (OWASP ASVS 5.0.0 V5.2.2): the allowlist
comes from what the standards' own examples attach, not from memory.

Walks every JSON resource under each directory given, and records every
object with a `contentType` (Attachment, Binary) as one row of counts:
content type, whether it carried inline `data`, the element path, and how
many times. Writes content_type_census.tsv, flushed per directory.

Run: python3 -I content_type_census.py <dir>...
"""
import collections
import json
import os
import sys

out = open('tool/review_2026-10-17/content_type_census.tsv', 'w')
out.write('source\tcontent_type\thas_data\tpath\tcount\n')
total_files = 0
for root in sys.argv[1:]:
    counts = collections.Counter()
    files = 0

    def walk(node, path):
        if isinstance(node, dict):
            here = node.get('resourceType')
            if isinstance(here, str):
                path = here
            ct = node.get('contentType')
            if isinstance(ct, str):
                counts[(ct, 'data' in node, path)] += 1
            for k, v in node.items():
                walk(v, f'{path}.{k}')
        elif isinstance(node, list):
            for v in node:
                walk(v, path)

    for dirpath, _, names in os.walk(root):
        for name in names:
            if not name.endswith('.json'):
                continue
            try:
                with open(os.path.join(dirpath, name), encoding='utf-8') as f:
                    doc = json.load(f)
            except (OSError, ValueError):
                continue
            files += 1
            walk(doc, '')
    total_files += files
    for (ct, has_data, path), n in sorted(counts.items(),
                                          key=lambda kv: -kv[1]):
        out.write(f'{root}\t{ct}\t{has_data}\t{path}\t{n}\n')
    out.flush()
    print(root, 'files', files, 'contentType objects', sum(counts.values()),
          flush=True)
out.close()
