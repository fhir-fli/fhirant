#!/usr/bin/env bash
# What clamav/clamav:1.5.4 says about password-protected files, in two arms:
# as-is is fhirant's clamav/clamd.conf unchanged; alert-encrypted adds the
# AlertEncrypted option, which ClamAV's clamd.conf.sample (read 2026-10-21,
# clamd.conf.image-default here) describes as alerting on encrypted zip,
# 7zip, rar and pdf. Samples come from make_encrypted_samples.py, which
# needs pypdf and msoffcrypto-tool: pass the python that has them. One row
# per file and arm to encrypted_samples.tsv.
#
# Run from packages/fhirant_server:
#   tool/review_2026-10-17/clamd/encrypted_samples.sh <python>
set -u
python=$1
here=tool/review_2026-10-17/clamd
conf=$(cd ../.. && pwd)/clamav/clamd.conf
samples=/tmp/claude-1000/encsamples
name=fhirant-clamd-encrypted
port=13311
"$python" -I "$here/make_encrypted_samples.py" "$samples" || exit 1
out="$here/encrypted_samples.tsv"
printf 'arm\tfile\tbytes\tresult\n' > "$out"

run_arm() {
  local arm=$1 file=$2
  docker rm -f "$name" >/dev/null 2>&1
  docker run -d --name "$name" -p 127.0.0.1:$port:3310 \
    --mount "type=bind,source=$file,target=/etc/clamav/clamd.conf,readonly" \
    clamav/clamav:1.5.4 >/dev/null || return 1
  local ready=no
  for i in $(seq 1 360); do
    if docker exec "$name" clamdcheck.sh >/dev/null 2>&1; then ready=yes; break; fi
    sleep 1
  done
  echo "$arm: clamd ready=$ready after ${i}s"
  if [ "$ready" = yes ]; then
    dart run "$here/scan_files.dart" $port "$out" "$arm" \
      "$samples"/plain.zip "$samples"/encrypted.zip \
      "$samples"/plain.pdf "$samples"/user_pw.pdf "$samples"/owner_only.pdf \
      "$samples"/plain.docx "$samples"/encrypted.docx
  fi
  docker rm -f "$name" >/dev/null
}

run_arm as-is "$conf"
alert=/tmp/claude-1000/clamd-alert-encrypted.conf
{ cat "$conf"; echo 'AlertEncrypted yes'; } > "$alert"
run_arm alert-encrypted "$alert"
