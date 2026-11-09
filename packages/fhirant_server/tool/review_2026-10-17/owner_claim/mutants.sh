#!/bin/bash
# Breaks one rule of the owner claim at a time (auth/owner_claim.dart) and
# runs owner_claim_test.dart; each mutant must fail it. Writes one row per
# mutant to mutants.tsv as it finishes. Run from packages/fhirant_server.
DIR=tool/review_2026-10-17/owner_claim
OUT=$DIR/mutants.tsv
echo -e "mutant\tfile\texit\tfailed" > $OUT
mutate() { # name file old new [old new ...]
  name=$1; file=$2; shift 2
  cp "$file" "$file.orig"
  python3 -I -c "
import sys
p=sys.argv[1]; s=open(p).read(); a=sys.argv[2:]
for o,n in zip(a[::2],a[1::2]):
    assert s.count(o)==1,o
    s=s.replace(o,n)
open(p,'w').write(s)" "$file" "$@" || { mv "$file.orig" "$file"; echo -e "$name\t$file\tNOAPPLY\t-" >> $OUT; return; }
  dart test test/integration/owner_claim_test.dart > "$DIR/mutant_$name.log" 2>&1
  rc=$?
  failed=$(grep -cE '\[E\]$' "$DIR/mutant_$name.log")
  mv "$file.orig" "$file"
  echo -e "$name\t$file\t$rc\t$failed" >> $OUT
}
STORE=../fhirant_db/lib/db/fhirant_db.dart
# The administrator chooses a new account's password.
mutate admin_chooses lib/src/handlers/register_handler.dart \
  "if (body.containsKey('password')) {" "if (false) {"
# The reset takes the administrator's new_password.
mutate reset_takes_body lib/src/handlers/account_handler.dart \
  "    if (body.isNotEmpty) {" "    if (false) {"
# The reset leaves the old password working.
mutate reset_keeps_password lib/src/handlers/account_handler.dart \
  "    none.hash,
    none.salt," \
  "    user.passwordHash,
    user.salt,"
# The administrator is handed a secret that opens the account: the new
# account's password is one the registration reply carries.
mutate register_hands_secret lib/src/handlers/register_handler.dart \
  "      final none = await unusablePassword();" \
  "      final leakSalt = PasswordHasher.generateSalt();
      final none = (
        hash: await PasswordHasher.hashPassword('Leaked-Secret-1', leakSalt),
        salt: leakSalt,
      );" \
  "          'awaiting_owner_until': awaitingOwnerUntil.toUtc().toIso8601String()," \
  "          'awaiting_owner_until': awaitingOwnerUntil.toUtc().toIso8601String(),
          'leak': 'Leaked-Secret-1',"
# Any code approves.
mutate any_code_approves $STORE \
  "        if (held != code) {" "        if (false) {"
# A claim is held for an account that is not waiting.
mutate claim_without_wait $STORE \
  "'claim_code = ? WHERE username = ? AND awaiting_owner_until > ?'," \
  "'claim_code = ? WHERE username = ? AND (awaiting_owner_until > ? OR 1)',"
# The wait never runs out.
mutate no_expiry $STORE \
  "        if (!until.isAfter(DateTime.now())) return ClaimApproval.expired;" ""
# A non-administrator approves.
mutate anyone_approves lib/src/handlers/account_handler.dart \
  "  final refused = _requireAdmin(request);
  if (refused != null) return refused;
  final body = await _body(request);
  final raw = body?['code'];" \
  "  final body = await _body(request);
  final raw = body?['code'];"
# /auth/claim leaves the credential rate limit.
mutate claim_unlimited lib/src/fhirant_server.dart \
  "    'auth/claim'," ""
cat $OUT
