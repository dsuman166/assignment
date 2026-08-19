#!/usr/bin/env bash
# Simple smoke test: hits the app's HTTP endpoints and fails (non-zero exit)
# if any expected response is missing/wrong.
set -euo pipefail

BASE_URL="${1:-http://localhost:5000}"
MAX_RETRIES=20
SLEEP_SECONDS=3

echo "Running smoke test against ${BASE_URL}"

wait_for_endpoint() {
  local path="$1"
  local attempt=1
  until curl -fsS "${BASE_URL}${path}" > /tmp/smoke_response.json; do
    if [ "${attempt}" -ge "${MAX_RETRIES}" ]; then
      echo "FAILED: ${path} did not become available after ${MAX_RETRIES} attempts"
      exit 1
    fi
    echo "Attempt ${attempt}: ${path} not ready yet, retrying in ${SLEEP_SECONDS}s..."
    attempt=$((attempt + 1))
    sleep "${SLEEP_SECONDS}"
  done
}

echo "1) Checking /health ..."
wait_for_endpoint "/health"
grep -q '"status": *"ok"' /tmp/smoke_response.json || grep -q '"status":"ok"' /tmp/smoke_response.json
echo "   OK"

echo "2) Checking / (hello world message) ..."
wait_for_endpoint "/"
grep -qi "message" /tmp/smoke_response.json
echo "   OK"

echo "3) Checking /ready (DB connectivity) ..."
wait_for_endpoint "/ready"
grep -q '"db": *"reachable"' /tmp/smoke_response.json || grep -q '"db":"reachable"' /tmp/smoke_response.json
echo "   OK"

echo "4) Checking /db-time (actual query round-trip) ..."
wait_for_endpoint "/db-time"
grep -qi "db_time" /tmp/smoke_response.json
echo "   OK"

echo "All smoke tests passed."
