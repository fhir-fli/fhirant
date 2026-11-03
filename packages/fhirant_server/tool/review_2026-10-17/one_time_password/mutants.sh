#!/bin/bash
# Breaks one rule at a time and runs one_time_password_test.dart; each
# mutant must fail it. Run from packages/fhirant_server.
OUT=tool/review_2026-10-17/one_time_password/mutants.tsv
echo -e "mutant\tfile\texit\tfailed" > $OUT
mutate() { # name file python-replacement(old new)
  cp "$2" "$2.orig"
  python3 -I -c "import sys;p=sys.argv[1];s=open(p).read();o=sys.argv[2];assert s.count(o)==1,o;open(p,'w').write(s.replace(o,sys.argv[3]))" "$2" "$3" "$4" || { mv "$2.orig" "$2"; echo -e "$1\t$2\tNOAPPLY\t-" >> $OUT; return; }
  dart test test/integration/one_time_password_test.dart > "tool/review_2026-10-17/one_time_password/mutant_$1.log" 2>&1
  rc=$?
  failed=$(grep -cE '\[E\]$' "tool/review_2026-10-17/one_time_password/mutant_$1.log")
  mv "$2.orig" "$2"
  echo -e "$1\t$2\t$rc\t$failed" >> $OUT
}
mutate no_expiry lib/src/auth/credential_check.dart \
  "if (temporaryUntil != null && !temporaryUntil.isAfter(DateTime.now())) {" \
  "if (false) {"
mutate keep_one_time lib/src/handlers/account_handler.dart \
  "if (next == current) {" "if (false) {"
mutate login_opens_session lib/src/auth/credential_check.dart \
  "  return temporaryUntil == null
      ? CredentialOk(user)
      : CredentialMustChange(user);" "  return CredentialOk(user);"
mutate admin_chooses lib/src/handlers/register_handler.dart \
  "if (body.containsKey('password')) {" "if (false) {"
mutate reset_not_temporary lib/src/handlers/account_handler.dart \
  "await _setPassword(dbInterface, userId, once, temporaryUntil: until);" \
  "await _setPassword(dbInterface, userId, once);"
cat $OUT
