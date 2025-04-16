#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# Usage message
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $0 [clustername] [auth_key]"
  echo "Example: $0 walldorf c2ItZTAzZ..."
  echo "You can also export AUTH_KEY as an environment variable."
  exit 0
fi

# Inputs
CLUSTER_NAME="${1:-walldorf}"
AUTH_KEY="${2:-$AUTH_KEY}"

if [[ -z "$AUTH_KEY" ]]; then
  echo "❌ Error: No auth key provided. Pass as second argument or set AUTH_KEY env var."
  exit 1
fi

# Domain construction
APP_DOMAIN="apps.${CLUSTER_NAME}.ocp.vslen"
HOST="eic.${APP_DOMAIN}"
AUTH_HEADER="Authorization: Basic ${AUTH_KEY}"

# List of endpoints
ENDPOINTS=(
  "/http/test1"
  "/http/testelster"
  "/slvredis"
  "/httpbinipfilter"
)

echo "Using clustername: $CLUSTER_NAME"
echo "Using domain: ${HOST}"
echo "Using auth key: ${AUTH_KEY:0:5}...[REDACTED]"

# Run curl for each endpoint
for path in "${ENDPOINTS[@]}"; do
  echo "Testing endpoint: $path"
  curl -k --request GET \
    --url "https://${HOST}${path}" \
    --header "${AUTH_HEADER}" \
    --dump-header -
  echo -e "\n-----------------------------\n"
  sleep 1
done
