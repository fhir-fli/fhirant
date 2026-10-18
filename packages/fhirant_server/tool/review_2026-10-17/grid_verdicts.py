#!/usr/bin/env python3
"""Reads access_grid.tsv and writes every row that breaks an expectation to
grid_flags.tsv. The expectations come from outside the code:

- A credential that no longer stands (none, forged, expired, refresh token
  as access token, or one issued before the account was deactivated,
  demoted, reset, narrowed or logged out) gets 401 on every route that is
  not public (OWASP ASVS 5.0 V7 session management; the server's own
  rule that an account change ends earlier sessions).
- user/*.rs may not write; user/*.* may not use admin or system routes
  (SMART App Launch 2.2 scopes).
- A patient/ scope sees and touches only its patient's compartment
  (R4B security.html; SMART patient context).
- No request is answered 5xx or drops the connection.

Run: python3 -I tool/review_2026-10-17/grid_verdicts.py
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))

PUBLIC = {
    'status', 'register-admin', 'login-bad', 'refresh-own', 'revoke-own',
    'authorize-get', 'authorize-post', 'password-own', 'logout', 'base',
    'favicon', 'health', 'metadata', 'smart-config', 'health-query',
    'metadata-mode', 'metadata-post', 'auth-prefix-unknown',
    'auth-prefix-nested', 'wellknown-unknown',
}
DEAD = {'none', 'garbage', 'wrong-secret', 'alg-none', 'refresh-as-access',
        'expired', 'deactivated', 'demoted', 'pw-reset', 'scopes-narrowed',
        'logged-out'}
# Public routes that must not act for a credential that no longer stands.
ACTS_FOR_CALLER = {'register-admin', 'refresh-own', 'password-own'}
ADMIN = {'unlock', 'users', 'reset-pw', 'set-scopes', 'set-role',
         'deactivate', 'activate', 'register-admin'}
SYSTEM = {'export-sys', 'reindex', 'reindex-status', 'backup',
          'restore-garbage', 'create-searchparam', 'audit-update',
          'audit-delete'}
WRITES = {'meta-add-out', 'meta-delete-out', 'bundle-tx-write-out',
          'create-out', 'create-in', 'create-searchparam',
          'create-subscription-out', 'update-out', 'update-in',
          'update-create-out', 'cond-update-out', 'patch-out',
          'audit-update', 'audit-delete', 'delete-out', 'cond-delete-out',
          'delete-in', 'export-delete-roots', 'override-delete'}
OUT_WRITES = {w for w in WRITES if w.endswith('-out')}
IN_WRITES = {'create-in', 'update-in', 'delete-in'}


def ok(s):
    return s.isdigit() and 200 <= int(s) < 300


def verdicts(row):
    ident, label, s = row['identity'], row['label'], row['status']
    out = row['out_mark'] == 'True'
    v = []
    if not s.isdigit():
        if label != 'post:evil-accounts':
            v.append('no HTTP answer')
    elif int(s) >= 500:
        v.append('5xx')
    if label == 'post:evil-accounts':
        if row['body'] not in ('[]', ''):
            v.append('an account was created: ' + row['body'])
        return v
    if ident in DEAD:
        if label not in PUBLIC and s != '401':
            v.append('stale or forged credential not refused')
        if label in ACTS_FOR_CALLER and ok(s):
            v.append('public route acted for a dead credential')
        if out:
            v.append('out-of-compartment data to a dead credential')
    if ident == 'rdonly' and (label in WRITES or label in ADMIN) and ok(s):
        v.append('read-only account wrote')
    if ident == 'clin' and (label in ADMIN or label in SYSTEM) and ok(s):
        v.append('clinician used an admin/system route')
    if ident in ('pat', 'patro'):
        if out:
            v.append('out-of-compartment data to a patient scope')
        if label in OUT_WRITES and ok(s):
            v.append('patient scope wrote outside its compartment')
        if (label in ADMIN or label in SYSTEM) and ok(s):
            v.append('patient scope used an admin/system route')
        if ident == 'patro' and label in IN_WRITES and ok(s):
            v.append('patient read-only scope wrote')
    return v


def main():
    rows = list(csv.DictReader(open(os.path.join(HERE, 'access_grid.tsv')),
                               delimiter='\t'))
    path = os.path.join(HERE, 'grid_flags.tsv')
    n = 0
    with open(path, 'w') as f:
        f.write('identity\tlabel\tstatus\tverdict\tpath\tbody\n')
        for r in rows:
            if r['identity'].startswith('#'):
                continue
            for v in verdicts(r):
                n += 1
                f.write('\t'.join([r['identity'], r['label'], r['status'], v,
                                   r['path'], r['body'][:160]]) + '\n')
                f.flush()
    print('%d rows, %d flags -> %s' % (len(rows), n, path), flush=True)


if __name__ == '__main__':
    main()
