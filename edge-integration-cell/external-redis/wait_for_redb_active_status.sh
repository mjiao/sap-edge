#!/bin/bash

# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -uo pipefail

# Determine CLI tool (KUBE_CLI env var or oc)
if [[ -n "${KUBE_CLI:-}" ]] && command -v "${KUBE_CLI}" &> /dev/null; then
    : # KUBE_CLI already set from environment
elif command -v oc &> /dev/null; then
    KUBE_CLI="oc"
elif command -v kubectl &> /dev/null; then
    KUBE_CLI="kubectl"
else
    echo "Error: Neither oc nor kubectl found in PATH"
    exit 1
fi

# Default values
NAMESPACE="sap-eic-external-redis"
DATABASE_NAME="redb"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for RedisEnterpriseDatabase to reach active status.

OPTIONS:
    -n, --namespace NAMESPACE    Namespace where Redis is deployed (default: sap-eic-external-redis)
    -h, --help                   Display this help message

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

database_name="$DATABASE_NAME"
namespace="$NAMESPACE"

# Loop until status equals "active"
while true; do
    status=$($KUBE_CLI get RedisEnterpriseDatabase "$database_name" -n "$namespace" -o json | jq -r '.status.status')

    if [[ "$status" == "active" ]]; then
        echo "Redis Enterprise Database Status is active. Exiting loop."
        break
    else
        echo "Redis Enterprise Database Status is $status. Waiting..."
        sleep 10  # Adjust the sleep time as needed
    fi
done
