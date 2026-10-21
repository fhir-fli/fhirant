#!/usr/bin/env bash
# Starts clamav/clamav:1.5.4 with fhirant's clamav/clamd.conf, records how
# long clamd takes to answer PING (ready.txt, one line per poll), runs
# scan_timing.dart against it, and removes the container.
#
# Run from packages/fhirant_server:
#   tool/review_2026-10-17/clamd/measure.sh
set -u
here=tool/review_2026-10-17/clamd
conf=$(cd ../.. && pwd)/clamav/clamd.conf
name=fhirant-clamd-measure
port=13310
scratch=/tmp/claude-1000/clamd-measure
mkdir -p "$scratch"

# Zips: one holding EICAR (proves clamd reads the zip at all), and two whose
# one member expands past a limit: 150 MiB (MaxFileSize, default 100M) and
# 450 MiB (MaxScanSize, default 400M). Plain zips with the size in the
# header, no zip64. The first run of this script wrote the 450 MiB one as
# zip64 with a streamed size, and clamd called it clean.
python3 -I - "$scratch" <<'EOF2'
import sys, zipfile
d = sys.argv[1]
eicar = rb'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
with zipfile.ZipFile(f'{d}/eicar.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('eicar.com', eicar)
for mib in (150, 450):
    with zipfile.ZipFile(f'{d}/zeros_{mib}.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        info = zipfile.ZipInfo('zeros.bin')
        info.compress_type = zipfile.ZIP_DEFLATED
        info.file_size = mib * 1024 * 1024
        with z.open(info, 'w') as f:
            block = bytes(1024 * 1024)
            for _ in range(mib):
                f.write(block)
EOF2
ls -l "$scratch"

docker rm -f "$name" >/dev/null 2>&1
start=$(date +%s)
docker run -d --name "$name" -p 127.0.0.1:$port:3310 \
  --mount "type=bind,source=$conf,target=/etc/clamav/clamd.conf,readonly" \
  clamav/clamav:1.5.4 >/dev/null || exit 1

: > "$here/ready.txt"
ready=no
for i in $(seq 1 360); do
  reply=$( (exec 3<>/dev/tcp/127.0.0.1/$port && printf 'zPING\0' >&3 &&
    timeout 2 cat <&3 | tr -d '\0') 2>/dev/null)
  echo "$(( $(date +%s) - start ))s poll $i: ${reply:-no answer}" >> "$here/ready.txt"
  if [ "$reply" = "PONG" ]; then ready=yes; break; fi
  sleep 1
done
echo "ready=$ready after $(( $(date +%s) - start ))s" | tee -a "$here/ready.txt"
docker exec "$name" grep -i AlertExceedsMax /etc/clamav/clamd.conf >> "$here/ready.txt"

if [ "$ready" = yes ]; then
  dart run "$here/scan_timing.dart" $port "$scratch/eicar.zip" "$scratch/zeros_150.zip" "$scratch/zeros_450.zip"
  echo "scan_timing exit=$?"
fi
docker exec "$name" cat /var/log/clamav/clamd.log > "$here/clamd.log" 2>&1
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' "$name" >> "$here/ready.txt"
docker rm -f "$name" >/dev/null
