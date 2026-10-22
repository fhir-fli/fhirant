#!/usr/bin/env bash
# test_docker.sh — Build, start, and smoke-test the FHIRant Docker container.
#
# Run from the fhirant/ directory:
#   ./test_docker.sh

set -euo pipefail

CONTAINER_NAME="fhirant-test-$$"
IMAGE_NAME="fhirant-test"
PORT=18080
ENCRYPTION_KEY="test-encryption-key"
JWT_SECRET="test-jwt-secret"
BASE="http://localhost:$PORT"
PASS=0
FAIL=0
# A first boot loads the FHIR specification before the server listens:
# 31 s measured 2026-10-18 on the review desktop (REVIEW-2026-10-17 finding
# 20, tool/review_2026-10-17/docker_probe.txt), and this script used to give
# up at 30. Four times that, so a slower machine is not a failure.
BOOT_WAIT=120

# X-Forwarded-For is OVERWRITTEN by the server with the connection address
# (_trustedClientIpMiddleware), so every request here shares one rate-limit
# bucket; the credential endpoints allow 10 per 60 s and this script makes
# fewer than that. The three addresses are kept for readability only.
PROBE_IP="10.0.0.99"
TEST_IP="10.0.0.1"
TEST_IP2="10.0.0.2"

cleanup() {
  echo ""
  echo "=== Cleaning up ==="
  docker rm -f "$CONTAINER_NAME" "fhirant-scan-$$" "fhirant-clamav-$$" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

assert_status() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $description (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected body to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# --- Build ---
echo "=== Building Docker image ==="
docker build -f Dockerfile -t "$IMAGE_NAME" . || {
  echo "FAIL: Docker build failed"
  exit 1
}
echo ""

# --- Start ---
echo "=== Starting container ==="
docker run -d --name "$CONTAINER_NAME" \
  -p "$PORT:8080" \
  -e "FHIRANT_ENCRYPTION_KEY=$ENCRYPTION_KEY" \
  -e "FHIRANT_JWT_SECRET=$JWT_SECRET" \
  "$IMAGE_NAME"

# --- Wait for healthy (uses separate IP so probes don't eat test rate-limit) ---
echo "=== Waiting for server to be ready ==="
READY=false
for i in $(seq 1 "$BOOT_WAIT"); do
  if curl -sf -H "X-Forwarded-For: $PROBE_IP" "$BASE/metadata" >/dev/null 2>&1; then
    READY=true
    echo "  Server ready after ${i}s"
    break
  fi
  sleep 1
done

if [ "$READY" = false ]; then
  echo "FAIL: Server did not start within ${BOOT_WAIT}s"
  echo "=== Container logs ==="
  docker logs "$CONTAINER_NAME"
  exit 1
fi
echo ""

# --- Test 0: Docker's own health check (REVIEW-2026-09-17 S5) ---
# The image's HEALTHCHECK asks the running server's /health. It used to run
# `server --help`, which says nothing about the server. The first check runs
# one interval (30 s) after start; allow two.
echo "=== Test: Docker health check ==="
HEALTH="starting"
for i in $(seq 1 75); do
  HEALTH=$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME")
  [ "$HEALTH" = "starting" ] || break
  sleep 1
done
if [ "$HEALTH" = "healthy" ]; then
  echo "  PASS: container reports healthy"
  PASS=$((PASS + 1))
else
  echo "  FAIL: container health is '$HEALTH'"
  FAIL=$((FAIL + 1))
fi
PROBE=$(docker inspect --format '{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME")
assert_contains "the health check read /health, not --help" '"status"' "$PROBE"
echo ""

# --- Test 1: GET /metadata (no auth required) ---
echo "=== Test: GET /metadata ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -H "X-Forwarded-For: $TEST_IP" "$BASE/metadata")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /metadata returns 200" 200 "$STATUS"
assert_contains "Response is a CapabilityStatement" '"resourceType":"CapabilityStatement"' "$BODY"
echo ""

# --- Test 2: Unauthenticated request returns 401 ---
echo "=== Test: Unauthenticated access ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Forwarded-For: $TEST_IP" "$BASE/Patient")
assert_status "GET /Patient without auth returns 401" 401 "$STATUS"
echo ""

# --- Test 2b: GET /auth/status (first user detection) ---
echo "=== Test: GET /auth/status (before registration) ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -H "X-Forwarded-For: $TEST_IP" "$BASE/auth/status")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /auth/status returns 200" 200 "$STATUS"
assert_contains "firstUser is true before registration" '"firstUser":true' "$BODY"
assert_contains "the first registration needs the bootstrap token" '"bootstrapTokenRequired":true' "$BODY"
echo ""

# --- Test 3: Register first user (bootstrap; REVIEW-2026-09-17 A15) ---
# With no FHIRANT_ADMIN_USERNAME/PASSWORD the server logs a one-time token
# at start; the first registration must carry it.
echo "=== Test: Register first user ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/register" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Content-Type: application/json" \
  -d '{"username": "testadmin", "password": "TestPass123!"}')
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "POST /auth/register without the bootstrap token is 403" 403 "$STATUS"

# The token is the line after "X-Bootstrap-Token header" in the log message.
BOOTSTRAP_TOKEN=$(docker logs "$CONTAINER_NAME" 2>&1 \
  | grep -oE 'body field\):\\n[A-Za-z0-9_=-]+' | head -1 | sed 's/.*\\n//')
if [ -z "$BOOTSTRAP_TOKEN" ]; then
  echo "  FAIL: no bootstrap token in the container log"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: bootstrap token found in the container log"
  PASS=$((PASS + 1))
fi
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/register" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Content-Type: application/json" \
  -H "X-Bootstrap-Token: $BOOTSTRAP_TOKEN" \
  -d '{"username": "testadmin", "password": "TestPass123!"}')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "POST /auth/register with the bootstrap token returns 201" 201 "$STATUS"
assert_contains "First user gets admin role" '"role":"admin"' "$BODY"
assert_contains "Register returns a JWT token" '"token":"' "$BODY"
assert_contains "Register returns a refresh token" '"refresh_token":"' "$BODY"
echo ""

# --- Test 3b: GET /auth/status (after registration) ---
echo "=== Test: GET /auth/status (after registration) ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -H "X-Forwarded-For: $TEST_IP" "$BASE/auth/status")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /auth/status returns 200" 200 "$STATUS"
assert_contains "firstUser is false after registration" '"firstUser":false' "$BODY"
echo ""

# --- Test 4: Login ---
echo "=== Test: Login ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/login" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Content-Type: application/json" \
  -d '{"username": "testadmin", "password": "TestPass123!"}')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "POST /auth/login returns 200" 200 "$STATUS"
TOKEN=$(echo "$BODY" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
if [ -n "$TOKEN" ]; then
  echo "  PASS: Login returned a JWT token"
  PASS=$((PASS + 1))
else
  echo "  FAIL: No token in login response"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 5: Create a Patient ---
echo "=== Test: Create Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/Patient" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Patient",
    "name": [{"family": "Docker", "given": ["Test"]}],
    "birthDate": "1990-01-15"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "POST /Patient returns 201" 201 "$STATUS"
assert_contains "Response contains Patient resourceType" '"resourceType":"Patient"' "$BODY"
PATIENT_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$PATIENT_ID" ]; then
  echo "  PASS: Patient created with ID $PATIENT_ID"
  PASS=$((PASS + 1))
else
  echo "  FAIL: No patient ID in response"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 6: Read the Patient back ---
echo "=== Test: Read Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/Patient/$PATIENT_ID" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient/$PATIENT_ID returns 200" 200 "$STATUS"
assert_contains "Read returns same patient" "\"id\":\"$PATIENT_ID\"" "$BODY"
assert_contains "Patient has correct family name" '"family":"Docker"' "$BODY"
echo ""

# --- Test 7: Search for the Patient ---
echo "=== Test: Search Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/Patient?name=Docker" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient?name=Docker returns 200" 200 "$STATUS"
assert_contains "Search returns a Bundle" '"resourceType":"Bundle"' "$BODY"
assert_contains "Bundle contains our patient" '"family":"Docker"' "$BODY"
echo ""

# --- Test 8: Update the Patient ---
echo "=== Test: Update Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$BASE/Patient/$PATIENT_ID" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d "{
    \"resourceType\": \"Patient\",
    \"id\": \"$PATIENT_ID\",
    \"name\": [{\"family\": \"Docker\", \"given\": [\"Updated\"]}],
    \"birthDate\": \"1990-01-15\"
  }")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "PUT /Patient returns 200" 200 "$STATUS"
assert_contains "Updated patient has new given name" '"Updated"' "$BODY"
echo ""

# --- Test 8b: bulk export (REVIEW-2026-10-17 finding 1) ---
# The export directory used to be relative to the working directory, /root
# in this image, which the server's user cannot write: every export failed
# with 500 "Export failed". It now lives under --db-path (/data).
echo "=== Test: Bulk export ==="
LOCATION=$(curl -s -D - -o /dev/null "$BASE/\$export?_type=Patient" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/fhir+json" \
  -H "Prefer: respond-async" \
  | grep -i '^content-location:' | tr -d '\r' | awk '{print $2}')
EXPORT_STATUS=none
MANIFEST=""
for i in $(seq 1 30); do
  RESPONSE=$(curl -s -w "\n%{http_code}" "$LOCATION" \
    -H "X-Forwarded-For: $TEST_IP" \
    -H "Authorization: Bearer $TOKEN")
  EXPORT_STATUS=$(echo "$RESPONSE" | tail -1)
  MANIFEST=$(echo "$RESPONSE" | head -n -1)
  [ "$EXPORT_STATUS" = "202" ] || break
  sleep 1
done
assert_status "the export completes" 200 "$EXPORT_STATUS"
FILE_URL=$(echo "$MANIFEST" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FILE_URL" \
  -H "X-Forwarded-For: $TEST_IP" \
  -H "Authorization: Bearer $TOKEN")
assert_status "the export file downloads" 200 "$STATUS"
echo ""

# Switch to second IP for remaining requests to stay within rate limit
# --- Test 9: Check history ---
echo "=== Test: Patient history ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/Patient/$PATIENT_ID/_history" \
  -H "X-Forwarded-For: $TEST_IP2" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient/<id>/_history returns 200" 200 "$STATUS"
assert_contains "History returns a Bundle" '"resourceType":"Bundle"' "$BODY"
echo ""

# --- Test 10: Delete the Patient ---
echo "=== Test: Delete Patient ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/Patient/$PATIENT_ID" \
  -H "X-Forwarded-For: $TEST_IP2" \
  -H "Authorization: Bearer $TOKEN")
assert_status "DELETE /Patient returns 204" 204 "$STATUS"
echo ""

# --- Test 11: Confirm deletion ---
echo "=== Test: Read deleted Patient ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/Patient/$PATIENT_ID" \
  -H "X-Forwarded-For: $TEST_IP2" \
  -H "Authorization: Bearer $TOKEN")
# FHIR spec: reading a deleted resource returns 410 Gone when the server
# tracks deletions (fhirant keeps delete tombstones in resource history).
assert_status "GET deleted patient returns 410" 410 "$STATUS"
echo ""

# --- Test 12: the administrator seeded from the environment (A15) ---
echo "=== Test: Administrator seeded from FHIRANT_ADMIN_USERNAME/PASSWORD ==="
SEED_CONTAINER="fhirant-seed-$$"
SEED_PORT=18081
SEED_BASE="http://localhost:$SEED_PORT"
docker run -d --name "$SEED_CONTAINER" \
  -p "$SEED_PORT:8080" \
  -e "FHIRANT_ENCRYPTION_KEY=$ENCRYPTION_KEY" \
  -e "FHIRANT_JWT_SECRET=$JWT_SECRET" \
  -e "FHIRANT_ADMIN_USERNAME=seededadmin" \
  -e "FHIRANT_ADMIN_PASSWORD=SeedPass123!" \
  "$IMAGE_NAME" >/dev/null
SEED_READY=false
for i in $(seq 1 "$BOOT_WAIT"); do
  if curl -sf "$SEED_BASE/metadata" >/dev/null 2>&1; then
    SEED_READY=true
    break
  fi
  sleep 1
done
if [ "$SEED_READY" = false ]; then
  echo "  FAIL: seeded container did not start within ${BOOT_WAIT}s"
  docker logs "$SEED_CONTAINER"
  FAIL=$((FAIL + 1))
else
  RESPONSE=$(curl -s -w "\n%{http_code}" "$SEED_BASE/auth/status")
  BODY=$(echo "$RESPONSE" | head -n -1)
  assert_contains "seeded server has its first user" '"firstUser":false' "$BODY"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SEED_BASE/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"username": "intruder", "password": "TestPass123!"}')
  STATUS=$(echo "$RESPONSE" | tail -1)
  assert_status "registration on the seeded server needs an administrator" 403 "$STATUS"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SEED_BASE/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username": "seededadmin", "password": "SeedPass123!"}')
  BODY=$(echo "$RESPONSE" | head -n -1)
  STATUS=$(echo "$RESPONSE" | tail -1)
  assert_status "the seeded administrator logs in" 200 "$STATUS"
  assert_contains "with the admin role" '"role":"admin"' "$BODY"
fi
docker rm -f "$SEED_CONTAINER" >/dev/null 2>&1 || true
echo ""

# --- Test 13: files are scanned by a real clamd (OWASP ASVS 5.0.0 V5.4.3) ---
# ClamAV's image with this repository's clamav/clamd.conf, as
# docker-compose.yml runs it. The fhirant container joins the clamav
# container's network namespace, so clamd is at 127.0.0.1 and no Docker
# network is created; fhirant's port is published on the clamav container.
# The EICAR test file is the standard known positive.
echo "=== Test: uploaded files are scanned by clamd ==="
CLAM_CONTAINER="fhirant-clamav-$$"
SCAN_CONTAINER="fhirant-scan-$$"
SCAN_PORT=18082
SCAN_BASE="http://localhost:$SCAN_PORT"
docker run -d --name "$CLAM_CONTAINER" \
  -p "$SCAN_PORT:8080" \
  --mount "type=bind,source=$PWD/clamav/clamd.conf,target=/etc/clamav/clamd.conf,readonly" \
  clamav/clamav:1.5.4 >/dev/null
# clamd answered PING 22 s after start on the review desktop (measured
# 2026-10-21, tool/review_2026-10-17/clamd/ready.txt); the image's own
# health check allows 360 s.
CLAM_READY=false
for i in $(seq 1 360); do
  if docker exec "$CLAM_CONTAINER" clamdcheck.sh >/dev/null 2>&1; then
    CLAM_READY=true
    echo "  clamd ready after ${i}s"
    break
  fi
  sleep 1
done
if [ "$CLAM_READY" = false ]; then
  echo "  FAIL: clamd did not answer within 360s"
  docker logs "$CLAM_CONTAINER"
  FAIL=$((FAIL + 1))
else
  docker run -d --name "$SCAN_CONTAINER" \
    --network "container:$CLAM_CONTAINER" \
    -e "FHIRANT_ENCRYPTION_KEY=$ENCRYPTION_KEY" \
    -e "FHIRANT_JWT_SECRET=$JWT_SECRET" \
    -e "FHIRANT_ADMIN_USERNAME=scanadmin" \
    -e "FHIRANT_ADMIN_PASSWORD=ScanPass123!" \
    "$IMAGE_NAME" /app/bin/server --port 8080 --db-path /data \
    --clamd-host 127.0.0.1 >/dev/null
  SCAN_READY=false
  for i in $(seq 1 "$BOOT_WAIT"); do
    if curl -sf "$SCAN_BASE/metadata" >/dev/null 2>&1; then
      SCAN_READY=true
      break
    fi
    sleep 1
  done
  if [ "$SCAN_READY" = false ]; then
    echo "  FAIL: scanning container did not start within ${BOOT_WAIT}s"
    docker logs "$SCAN_CONTAINER"
    FAIL=$((FAIL + 1))
  else
    SCAN_TOKEN=$(curl -s -X POST "$SCAN_BASE/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"username": "scanadmin", "password": "ScanPass123!"}' \
      | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    # base64 of the 68-byte EICAR string, and of "a clean file".
    EICAR_B64='WDVPIVAlQEFQWzRcUFpYNTQoUF4pN0NDKTd9JEVJQ0FSLVNUQU5EQVJELUFOVElWSVJVUy1URVNULUZJTEUhJEgrSCo='
    CLEAN_B64='YSBjbGVhbiBmaWxl'
    # A PDF that needs a password to open (pypdf, AES-256; made by
    # tool/review_2026-10-17/clamd/make_encrypted_samples.py as user_pw.pdf):
    # clamav/clamd.conf sets AlertEncrypted, so it cannot be stored unscanned.
    # A zip no longer reaches clamd: the type check refuses application/zip
    # first, which the zip case shows.
    LOCKED_B64=$(base64 -w0 "$(dirname "$0")/packages/fhirant_server/tool/review_2026-10-17/clamd/password_protected.pdf")
    ZIP_DIR=$(mktemp -d)
    printf 'a clinic letter\n' > "$ZIP_DIR/letter.txt"
    (cd "$ZIP_DIR" && zip -q letter.zip letter.txt)
    ZIP_B64=$(base64 -w0 "$ZIP_DIR/letter.zip")
    rm -rf "$ZIP_DIR"
    for CASE in clean eicar locked zip; do
      case "$CASE" in
        eicar) DATA=$EICAR_B64; TYPE=text/plain ;;
        locked) DATA=$LOCKED_B64; TYPE=application/pdf ;;
        zip) DATA=$ZIP_B64; TYPE=application/zip ;;
        *) DATA=$CLEAN_B64; TYPE=text/plain ;;
      esac
      RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$SCAN_BASE/Binary" \
        -H "Authorization: Bearer $SCAN_TOKEN" \
        -H "Content-Type: application/fhir+json" \
        -d "{\"resourceType\": \"Binary\", \"contentType\": \"$TYPE\", \"data\": \"$DATA\"}")
      BODY=$(echo "$RESPONSE" | head -n -1)
      STATUS=$(echo "$RESPONSE" | tail -1)
      if [ "$CASE" = eicar ]; then
        assert_status "the EICAR file is refused" 422 "$STATUS"
        assert_contains "named by clamd's signature" 'Eicar-Test-Signature' "$BODY"
      elif [ "$CASE" = locked ]; then
        assert_status "a password-protected PDF is refused" 422 "$STATUS"
        assert_contains "as encrypted" 'Heuristics.Encrypted.PDF' "$BODY"
      elif [ "$CASE" = zip ]; then
        assert_status "a zip is refused by its type" 422 "$STATUS"
        assert_contains "as a type not stored" 'which this server does not store' "$BODY"
      else
        assert_status "a clean file is stored" 201 "$STATUS"
      fi
    done
  fi
fi
docker rm -f "$SCAN_CONTAINER" "$CLAM_CONTAINER" >/dev/null 2>&1 || true
echo ""

# --- Summary ---
echo "==============================="
echo "  Results: $PASS passed, $FAIL failed"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "=== Container logs ==="
  docker logs "$CONTAINER_NAME"
  exit 1
fi
