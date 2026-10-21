"""Searches each cloned FHIR server for antivirus scanning and for any
handling of encrypted / password-protected files.

Known positive per repo: files mentioning the Binary resource (every FHIR
server has them); a repo with zero is a broken probe, not an absence.

Writes one line per hit to hits.tsv and a per-repo summary to summary.tsv,
flushed as it goes.

Run: python3 -I server_scan_search.py <clone root>
"""
import os
import re
import subprocess
import sys

root = sys.argv[1]
scan = re.compile(
    r'virus|malware|clam ?av|clamd|eicar|defender for storage|guardduty|'
    r'quarantin', re.I)
crypt = re.compile(
    r'password.?protect|encrypted (attachment|file|pdf|zip|document|archive)',
    re.I)
binary = re.compile(r'\bBinary\b')

hits = open(os.path.join(root, 'hits.tsv'), 'w')
hits.write('repo\tkind\tfile\tline\ttext\n')
summary = open(os.path.join(root, 'summary.tsv'), 'w')
summary.write('repo\tfiles\tbinary_files\tscan_hits\tcrypt_hits\n')
for repo in sorted(os.listdir(root)):
    path = os.path.join(root, repo)
    if not os.path.isdir(os.path.join(path, '.git')):
        continue
    files = subprocess.run(['git', '-C', path, 'ls-files'], capture_output=True,
                           text=True).stdout.splitlines()
    nbin = nscan = ncrypt = 0
    for f in files:
        full = os.path.join(path, f)
        try:
            if os.path.getsize(full) > 5_000_000:
                continue
            with open(full, 'rb') as fh:
                raw = fh.read()
        except OSError:
            continue
        if b'\0' in raw[:8000]:
            continue
        text = raw.decode('utf-8', 'replace')
        if binary.search(text):
            nbin += 1
        for n, line in enumerate(text.splitlines(), 1):
            for kind, rx in (('scan', scan), ('crypt', crypt)):
                if rx.search(line):
                    if kind == 'scan':
                        nscan += 1
                    else:
                        ncrypt += 1
                    hits.write(f'{repo}\t{kind}\t{f}\t{n}\t'
                               f'{line.strip()[:200]}\n')
                    hits.flush()
    summary.write(f'{repo}\t{len(files)}\t{nbin}\t{nscan}\t{ncrypt}\n')
    summary.flush()
    print(repo, len(files), nbin, nscan, ncrypt, flush=True)
