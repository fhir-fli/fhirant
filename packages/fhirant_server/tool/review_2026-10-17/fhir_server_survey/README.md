# Do open-source FHIR servers scan uploaded files?

Read 2026-10-21 for fhirant's antivirus scan (ASVS 5.0.0 V5.4.3), to decide
what to do with password-protected files.

`clone.log` names the ten repositories and the commit read (shallow clones).
`server_scan_search.py` searched every tracked text file for scanning words
(virus, malware, ClamAV, clamd, EICAR, GuardDuty, Defender for Storage,
quarantine) and for password-protected or encrypted files. Its known
positive is the word Binary, found in every repository (`summary.tsv`), so a
zero elsewhere is a real zero for those words, not a broken search.
`hits_outside_data_files.tsv` is every hit outside spec data files (.json,
.xml and so on, where "virus" is clinical text).

Result: only Medplum scans (`Binary/$scan` through Amazon GuardDuty; in
scan-every-upload mode only Binaries tagged NO_THREATS_FOUND are served, and
a password-protected archive is UNSUPPORTED, so not served). Microsoft's
hits are its own build pipeline's anti-malware task; Helios's are database
migration quarantine and encrypted bulk-submit transfers; the rest are
spec text. Firely Server's own code is not public; Spark is Firely's open
server. Searching words cannot see a scan done under other names, so this
says the words are absent, not that no file is ever checked.

Rerun: clone each repository in `clone.log` into one directory, then
`python3 -I server_scan_search.py <that directory>`.
