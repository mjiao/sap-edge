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

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for Redis Enterprise Operator to be ready.

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

namespace="$NAMESPACE"
redis_csv=""

while [ -z "$redis_csv" ]; do
    redis_csv=$($KUBE_CLI get subscription.operators.coreos.com redis-enterprise-operator-cert -n "$namespace" -o json | jq -r '.status.currentCSV')
    if [ -z "$redis_csv" ]; then
        echo "No Redis CSV found. Retrying..."
        sleep 5  # Adjust the sleep time as needed
    fi
done

echo "Found CSV from the subscription status: $redis_csv"

while true; do

    # Get CSVs in the namespace and filter by name containing "redis-enterprise-operator"
    csv_list=$($KUBE_CLI get csv -n "$namespace" --no-headers | grep 'redis-enterprise-operator')

    # Check if any CSVs were found
    if [ -z "$csv_list" ]; then
        echo "No CSVs found in namespace $namespace with 'redis-enterprise-operator' in their name."
    else
        echo "CSVs found in namespace $namespace with 'redis-enterprise-operator' in their name:"
        # Extract and print the CSV names
        while IFS= read -r csv_info; do
            redis_csv=$(echo "$csv_info" | awk '{print $1}')
            echo "Current CSV is $redis_csv"
        done <<< "$csv_list"
    fi
    phase=$($KUBE_CLI get csv "$redis_csv" -n "$namespace" -o json | jq -r '.status.phase')
    if [[ "$phase" == "Succeeded" ]]; then
        echo "Redis Operator installation is Succeeded."
        break
    else
        echo "Redis Operator installation is still $phase. Waiting..."
        sleep 5  # Adjust the sleep time as needed
    fi
done
