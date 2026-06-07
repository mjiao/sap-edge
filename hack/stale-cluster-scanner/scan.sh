#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
# SPDX-License-Identifier: Apache-2.0

# Scans ARO and ROSA clusters for stale instances older than THRESHOLD_HOURS
# and sends a summary to Slack via webhook.
#
# Required environment variables:
#   SLACK_WEBHOOK_URL       - Slack incoming webhook URL
#   AZURE_CLIENT_ID         - Azure service principal client ID
#   AZURE_CLIENT_SECRET     - Azure service principal secret
#   AZURE_TENANT_ID         - Azure tenant ID
#   AZURE_SUBSCRIPTION_ID   - Azure subscription ID
#   ROSA_TOKEN              - Red Hat OCM offline token
#   AWS_ACCESS_KEY_ID       - AWS access key (required by rosa CLI)
#   AWS_SECRET_ACCESS_KEY   - AWS secret key (required by rosa CLI)
#   AWS_DEFAULT_REGION      - AWS region (required by rosa CLI)
#
# Optional:
#   THRESHOLD_HOURS         - Age threshold in hours (default: 24)

set -euo pipefail

THRESHOLD_HOURS="${THRESHOLD_HOURS:-24}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL must be set}"

threshold_seconds=$((THRESHOLD_HOURS * 3600))
now_epoch=$(date +%s)

scan_aro() {
  if ! command -v az &>/dev/null; then
    echo "az CLI not found, skipping ARO scan" >&2
    return
  fi

  az login --service-principal \
    -u "${AZURE_CLIENT_ID}" \
    -p "${AZURE_CLIENT_SECRET}" \
    --tenant "${AZURE_TENANT_ID}" \
    --output none 2>/dev/null

  az account set --subscription "${AZURE_SUBSCRIPTION_ID}" 2>/dev/null

  local clusters
  clusters=$(az aro list --output json 2>/dev/null || echo "[]")

  echo "${clusters}" | jq -c '.[]' | while read -r cluster; do
    local name created_at resource_group
    name=$(echo "${cluster}" | jq -r '.name')
    created_at=$(echo "${cluster}" | jq -r '.createdAt // .systemData.createdAt // empty')
    resource_group=$(echo "${cluster}" | jq -r '.resourceGroup // "unknown"')

    [[ -z "${created_at}" ]] && continue

    local created_epoch
    created_epoch=$(date -d "${created_at}" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" +%s 2>/dev/null || echo "0")
    [[ "${created_epoch}" -eq 0 ]] && continue

    local age=$((now_epoch - created_epoch))
    if [[ ${age} -ge ${threshold_seconds} ]]; then
      local age_hours=$((age / 3600))
      echo "ARO|${name}|${resource_group}|${age_hours}h"
    fi
  done
}

scan_rosa() {
  if ! command -v rosa &>/dev/null; then
    echo "rosa CLI not found, skipping ROSA scan" >&2
    return
  fi

  rosa login --token="${ROSA_TOKEN}" 2>/dev/null || true

  local clusters
  clusters=$(rosa list clusters --output json 2>/dev/null || echo "[]")

  echo "${clusters}" | jq -c '.[]' | while read -r cluster; do
    local name created_at state
    name=$(echo "${cluster}" | jq -r '.name')
    created_at=$(echo "${cluster}" | jq -r '.creation_timestamp // empty')
    state=$(echo "${cluster}" | jq -r '.state // "unknown"')

    [[ -z "${created_at}" ]] && continue

    local created_epoch
    created_epoch=$(date -d "${created_at}" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" +%s 2>/dev/null || echo "0")
    [[ "${created_epoch}" -eq 0 ]] && continue

    local age=$((now_epoch - created_epoch))
    if [[ ${age} -ge ${threshold_seconds} ]]; then
      local age_hours=$((age / 3600))
      echo "ROSA|${name}|${state}|${age_hours}h"
    fi
  done
}

echo "Scanning ARO clusters..."
aro_results=$(scan_aro)
echo "Scanning ROSA clusters..."
rosa_results=$(scan_rosa)

all_results=""
[[ -n "${aro_results}" ]] && all_results+="${aro_results}"
[[ -n "${rosa_results}" ]] && all_results+=$'\n'"${rosa_results}"
all_results=$(echo "${all_results}" | sed '/^$/d')

if [[ -z "${all_results}" ]]; then
  payload=$(jq -n --arg hrs "${THRESHOLD_HOURS}" \
    '{"text": (":white_check_mark: *Stale Cluster Report* -- All clear! No clusters older than " + $hrs + " hours found.")}')
else
  count=$(echo "${all_results}" | wc -l | tr -d ' ')

  body=":warning: *Stale Cluster Report* -- ${count} cluster(s) older than ${THRESHOLD_HOURS} hours"
  body+=$'\n\n'"| Type | Name | Account/RG | Age |"
  body+=$'\n'"|------|------|-----------|-----|"

  while IFS='|' read -r type name account age rest; do
    body+=$'\n'"| ${type} | ${name} | ${account} | ${age} |"
  done <<< "${all_results}"

  if [ "${WEEKEND_REMINDER:-false}" = "true" ]; then
    body+=$'\n\n'":rotating_light: *WEEKEND ALERT* -- These clusters are running over the weekend! If you're not actively testing, please deprovision them now to save costs."
  else
    body+=$'\n\n'"Please clean up unused clusters to avoid unnecessary costs. Remember to deprovision clusters before the weekend if they are not needed."
  fi

  payload=$(jq -n --arg text "${body}" '{"text": $text}')
fi

response=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "${payload}" \
  "${SLACK_WEBHOOK_URL}")

if [[ "${response}" -eq 200 ]]; then
  echo "Slack notification sent successfully"
else
  echo "Failed to send Slack notification (HTTP ${response})"
  exit 1
fi
