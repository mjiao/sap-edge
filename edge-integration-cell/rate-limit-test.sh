#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# This script tests that an endpoint correctly returns a 429 status
# after being called several times in quick succession.

# --- Function to display usage ---
usage() {
  cat <<EOF
Usage: $0 --host <hostname> [OPTIONS] <endpoint_path>

Tests that an endpoint correctly returns a 429 status

Required Arguments:
  <endpoint_path>             The path of the endpoint to test (e.g., /http/test1).

Options:
  -H, --host <hostname>       The full hostname to test.
  -k, --auth-key <key>        The basic authentication key. (Env: AUTH_KEY)
  -i, --ingress-ip <ip>       The Ingress IP for internal resolution mode. (Env: INGRESS_IP)
  -p, --public-dns            Use public DNS for resolution (disables --resolve).
  -h, --help                  Show this help message.
EOF
  exit 1
}


# --- Argument Parsing ---
HOST="${HOST:-}"
AUTH_KEY="${AUTH_KEY:-}"
INGRESS_IP="${INGRESS_IP:-}"
USE_PUBLIC_DNS=false
ENDPOINT_PATH=""

# Parse flags first, then grab the final argument as the endpoint path
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host) HOST="$2"; shift 2 ;;
    -k|--auth-key) AUTH_KEY="$2"; shift 2 ;;
    -i|--ingress-ip) INGRESS_IP="$2"; shift 2 ;;
    -p|--public-dns) USE_PUBLIC_DNS=true; shift 1 ;;
    -h|--help) usage ;;
    # If it's not a flag, it must be the endpoint path
    -*) echo "❌ Unknown option: $1" >&2; usage ;;
    *) ENDPOINT_PATH="$1"; shift 1 ;;
  esac
done

# --- Configuration Validation ---
[[ -z "$HOST" ]] && { echo "❌ The --host argument is required." >&2; usage; }
[[ -z "$ENDPOINT_PATH" ]] && { echo "❌ The endpoint_path argument is required." >&2; usage; }
[[ -z "$AUTH_KEY" ]] && { echo "❌ No AUTH_KEY provided." >&2; exit 1; }
if ! $USE_PUBLIC_DNS && [[ -z "$INGRESS_IP" ]]; then
  echo "❌ No INGRESS_IP provided for internal resolution mode." >&2
  exit 1
fi

# --- Main Execution ---
echo "--------------------------------------------------"
echo "Target Host:    $HOST"
echo "Endpoint Path:  $ENDPOINT_PATH"

CURL_OPTS=()
if $USE_PUBLIC_DNS; then
  echo "Resolution:     Public DNS (--public-dns)"
else
  echo "Resolution:     Internal via --resolve ($INGRESS_IP)"
  CURL_OPTS+=("--resolve" "${HOST}:443:${INGRESS_IP}")
fi
echo "--------------------------------------------------"


echo "--- Triggering requests to activate rate limit for ${ENDPOINT_PATH} ---"

# --- This loop is non-blocking ---
echo "--- Launching parallel requests to activate rate limit for ${ENDPOINT_PATH} ---"

for i in {1..6}; do
    echo "Launching background warm-up request #$i..."
    # The "&" sends the command to the background and the loop continues immediately
    curl --silent --output /dev/null --insecure --request GET \
        -H "Authorization: Basic ${AUTH_KEY}" \
        "${CURL_OPTS[@]}" \
        --url "https://${HOST}${ENDPOINT_PATH}" &
done

# --- ADDED: wait command ---
# This command blocks until all background jobs launched by this script have finished.
# This ensures the warm-up is complete before we send the final test request.
wait
echo "--- All warm-up requests have completed. ---"
echo "--- Sending final request to check for 429 status ---"

# Create a temporary file to store the response body
RESPONSE_BODY_FILE=$(mktemp)
# Execute the final request and capture the HTTP status code
HTTP_STATUS=$(curl --write-out '%{http_code}' --silent --insecure --request GET \
    -H "Authorization: Basic ${AUTH_KEY}" \
    "${CURL_OPTS[@]}" \
    --url "https://${HOST}${ENDPOINT_PATH}" \
    --output "$RESPONSE_BODY_FILE")

echo "Received Status: $HTTP_STATUS"
echo "Received Body:"
cat "$RESPONSE_BODY_FILE"
echo "" # Newline for cleaner logs

# --- Validation ---
if [[ "$HTTP_STATUS" -ne 429 ]]; then
    echo "❌ FAILED: Expected HTTP status 429, but got '$HTTP_STATUS'."
    exit 1
fi
echo "✅ SUCCESS: Received correct HTTP status 429."

# Check if the response body contains the expected error code
if ! grep -q "surgeProtectionLimitExceeded" "$RESPONSE_BODY_FILE"; then
    echo "❌ FAILED: Response body did not contain 'surgeProtectionLimitExceeded'."
    exit 1
fi
echo "✅ SUCCESS: Response body contains correct error 'surgeProtectionLimitExceeded'."

echo "✅ Rate limit test passed for ${ENDPOINT_PATH}."
exit 0