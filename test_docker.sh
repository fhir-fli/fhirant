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
PASS=0
FAIL=0

cleanup() {
  echo ""
  echo "=== Cleaning up ==="
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
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
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected body to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# --- Build ---
echo "=== Building Docker image ==="
docker build -f Dockerfile -t "$IMAGE_NAME" .. || {
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

# --- Wait for healthy ---
echo "=== Waiting for server to be ready ==="
READY=false
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/metadata" >/dev/null 2>&1; then
    READY=true
    echo "  Server ready after ${i}s"
    break
  fi
  sleep 1
done

if [ "$READY" = false ]; then
  echo "FAIL: Server did not start within 30s"
  echo "=== Container logs ==="
  docker logs "$CONTAINER_NAME"
  exit 1
fi
echo ""

# --- Test 1: GET /metadata (no auth required) ---
echo "=== Test: GET /metadata ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "http://localhost:$PORT/metadata")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /metadata returns 200" 200 "$STATUS"
assert_contains "Response is a CapabilityStatement" '"resourceType":"CapabilityStatement"' "$BODY"
echo ""

# --- Test 2: Unauthenticated request returns 401 ---
echo "=== Test: Unauthenticated access ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/Patient")
assert_status "GET /Patient without auth returns 401" 401 "$STATUS"
echo ""

# --- Test 3: Register first user (bootstrap) ---
echo "=== Test: Register first user ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:$PORT/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"username": "testadmin", "password": "TestPass123!"}')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "POST /auth/register returns 201" 201 "$STATUS"
assert_contains "First user gets admin role" '"role":"admin"' "$BODY"
echo ""

# --- Test 4: Login ---
echo "=== Test: Login ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:$PORT/auth/login" \
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
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:$PORT/Patient" \
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
RESPONSE=$(curl -s -w "\n%{http_code}" "http://localhost:$PORT/Patient/$PATIENT_ID" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient/$PATIENT_ID returns 200" 200 "$STATUS"
assert_contains "Read returns same patient" "\"id\":\"$PATIENT_ID\"" "$BODY"
assert_contains "Patient has correct family name" '"family":"Docker"' "$BODY"
echo ""

# --- Test 7: Search for the Patient ---
echo "=== Test: Search Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "http://localhost:$PORT/Patient?name=Docker" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient?name=Docker returns 200" 200 "$STATUS"
assert_contains "Search returns a Bundle" '"resourceType":"Bundle"' "$BODY"
assert_contains "Bundle contains our patient" '"family":"Docker"' "$BODY"
echo ""

# --- Test 8: Update the Patient ---
echo "=== Test: Update Patient ==="
RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "http://localhost:$PORT/Patient/$PATIENT_ID" \
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
assert_contains "Updated patient has new given name" '"given":["Updated"]' "$BODY"
echo ""

# --- Test 9: Check history ---
echo "=== Test: Patient history ==="
RESPONSE=$(curl -s -w "\n%{http_code}" "http://localhost:$PORT/Patient/$PATIENT_ID/_history" \
  -H "Authorization: Bearer $TOKEN")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -1)
assert_status "GET /Patient/<id>/_history returns 200" 200 "$STATUS"
assert_contains "History returns a Bundle" '"resourceType":"Bundle"' "$BODY"
echo ""

# --- Test 10: Delete the Patient ---
echo "=== Test: Delete Patient ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "http://localhost:$PORT/Patient/$PATIENT_ID" \
  -H "Authorization: Bearer $TOKEN")
assert_status "DELETE /Patient returns 204" 204 "$STATUS"
echo ""

# --- Test 11: Confirm deletion ---
echo "=== Test: Read deleted Patient ==="
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/Patient/$PATIENT_ID" \
  -H "Authorization: Bearer $TOKEN")
assert_status "GET deleted patient returns 410" 410 "$STATUS"
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
