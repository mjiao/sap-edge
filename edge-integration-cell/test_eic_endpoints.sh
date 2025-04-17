#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# Usage message
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage: $0 [clustername|full_host] [auth_key]
Examples:
  # by cluster name (uses default host logic)
  $0 walldorf c2ItZTAzZ...
  # by full host
  $0 eic.apps.sapeic-mj.saponrhel.org c2ItZTAzZ...
You can also export AUTH_KEY as an environment variable.
EOF
  exit 0
fi

# Inputs
ARG1="${1:-}"           # could be cluster name or full host
ARG2="${2:-$AUTH_KEY}"  # auth key or fallback to env

if [[ -z "$ARG2" ]]; then
  echo "❌ Error: No auth key provided. Pass as second argument or set AUTH_KEY env var."
  exit 1
fi

# Determine HOST vs CLUSTER_NAME
if [[ "$ARG1" == *.* ]]; then
  # If it contains a dot, treat it as full host
  HOST="$ARG1"
  CLUSTER_NAME="(custom host)"
else
  # Otherwise build from cluster name
  CLUSTER_NAME="${ARG1:-walldorf}"
  APP_DOMAIN="apps.${CLUSTER_NAME}.ocp.vslen"
  HOST="eic.${APP_DOMAIN}"
fi

AUTH_KEY="$ARG2"
AUTH_HEADER="Authorization: Basic ${AUTH_KEY}"

# List of endpoints
ENDPOINTS=(
  "/http/test1"
  "/http/testelster"
  "/slvredis"
  "/httpbinipfilter"
)

echo "Using clustername: $CLUSTER_NAME"
echo "Using host:      $HOST"
echo "Using auth key:  ${AUTH_KEY:0:5}...[REDACTED]"

# Run curl for each endpoint
for path in "${ENDPOINTS[@]}"; do
  echo -e "\n🔍 Testing endpoint: $path"
  curl --insecure --request GET \
       --url "https://${HOST}${path}" \
       --header "${AUTH_HEADER}" \
       --dump-header -
  echo -e "\n-----------------------------"
  sleep 1
done
