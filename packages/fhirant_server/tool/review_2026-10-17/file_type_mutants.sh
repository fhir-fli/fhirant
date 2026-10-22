#!/usr/bin/env bash
# Are the file-type tests evidence? Breaks one rule at a time in
# lib/src/utils/file_type.dart and lib/src/utils/file_data.dart, runs the
# tests that cover them, and restores the file. Every row should say
# "Some tests failed": a break the tests pass is a rule nothing checks.
# One row per break to file_type_mutants.tsv, written as each finishes.
#
# Run from packages/fhirant_server:
#   tool/review_2026-10-17/file_type_mutants.sh
set -u
here=tool/review_2026-10-17
out=$here/file_type_mutants.tsv
logs=$(mktemp -d /tmp/claude-1000/file_type_mutants.XXXXXX)
printf 'mutant\tfile\tresult\n' > "$out"

mutate() {
  local name=$1 file=$2 from=$3 to=$4
  cp "$file" "$logs/keep"
  if ! python3 -I -c '
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s:
    sys.exit(1)
open(p, "w").write(s.replace(a, b, 1))
' "$file" "$from" "$to"; then
    printf '%s\t%s\tpattern not found\n' "$name" "$file" >> "$out"
    return
  fi
  dart test test/utils/file_type_test.dart test/utils/file_data_test.dart \
    test/integration/file_type_routes_test.dart > "$logs/$name.log" 2>&1
  local result
  result=$(grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed|Some tests failed)' \
    "$logs/$name.log" | tail -n 1)
  cp "$logs/keep" "$file"
  printf '%s\t%s\t%s\n' "$name" "$file" "${result:-no result}" >> "$out"
  echo "$name: ${result:-no result}"
}

t=lib/src/utils/file_type.dart
d=lib/src/utils/file_data.dart
mutate no-html $t '  return !_looksLikeHtml(b);' '  return true;'
mutate mp3-any-layer $t '  if (layer != 1) return false;' '  if (layer == 9) return false;'
mutate no-charset $t "      !const {'utf-8', 'us-ascii'}.contains(charset)) {" '      false) {'
mutate jpeg-one-byte $t "'image/jpeg': (b) => _starts(b, const [0xFF, 0xD8, 0xFF])" "'image/jpeg': (b) => _starts(b, const [0xFF])"
mutate png-seven-bytes $t '      _starts(b, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),' '      _starts(b, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A]),'
mutate pdf-no-dash $t "'application/pdf': (b) => _starts(b, const [0x25, 0x50, 0x44, 0x46, 0x2D])" "'application/pdf': (b) => _starts(b, const [0x25, 0x50, 0x44, 0x46])"
mutate no-binary-byte $t '    if (_isBinaryDataByte(byte)) return false;' '    if (byte < 0) return false;'
mutate jose-any $t '  return _jwsCompact.hasMatch(utf8.decode(b).trim());' '  return true;'
mutate sniff-any-type $t '    if (sniffed == null || !_checks.containsKey(sniffed)) {' '    if (sniffed == null) {'
mutate sniff-no-html $t "  if (_looksLikeHtml(b)) return 'text/html';" '  if (b.isEmpty) return null;'
mutate no-json-parse $t '    jsonDecode(utf8.decode(b));' '    utf8.decode(b);'
mutate no-xml-parse $t '    XmlDocument.parse(utf8.decode(b));' '    utf8.decode(b);'
mutate not-a-file-removed $d "  'Attachment': 'hash',
  'AuditEventEntity': 'query',
  'DeviceUdiCarrier': 'carrierAIDC',
" ''
mutate attachment-type-optional $d "          type: node.contentType?.valueString,
          path: '\$path.contentType',
          required: true," "          type: node.contentType?.valueString,
          path: '\$path.contentType',
          required: false,"
rm -rf "$logs"
