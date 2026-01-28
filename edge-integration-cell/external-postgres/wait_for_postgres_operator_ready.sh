#!/bin/bash

# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -uo pipefail

# Determine CLI tool (KUBE_CLI env var or oc)
if [[ -n "${KUBE_CLI:-}" ]] && command -v "${KUBE_CLI}" &> /dev/null; then
    KUBE_CLI="${KUBE_CLI}"
elif command -v oc &> /dev/null; then
    KUBE_CLI="oc"
elif command -v kubectl &> /dev/null; then
    KUBE_CLI="kubectl"
else
    echo "Error: Neither oc nor kubectl found in PATH"
    exit 1
fi

# Default values
NAMESPACE="sap-eic-external-postgres"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for Crunchy Postgres Operator to be ready.

OPTIONS:
    -n, --namespace NAMESPACE    Namespace where PostgreSQL is deployed (default: sap-eic-external-postgres)
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
postgres_csv=""

while [ -z "$postgres_csv" ]; do
    postgres_csv=$($KUBE_CLI get subscription.operators.coreos.com crunchy-postgres-operator -n "$namespace" -o json | jq -r '.status.currentCSV')
    if [ -z "$postgres_csv" ]; then
        echo "No Postgres CSV found. Retrying..."
        sleep 5  # Adjust the sleep time as needed
    fi
done

while true; do

    # Get CSVs in the namespace and filter by name containing "postgresoperator"
    csv_list=$($KUBE_CLI get csv -n "$namespace" --no-headers | grep 'postgresoperator')

    # Check if any CSVs were found
    if [ -z "$csv_list" ]; then
        echo "No CSVs found in namespace $namespace with 'postgresoperator' in their name."
    else
        echo "CSVs found in namespace $namespace with 'postgresoperator' in their name:"
        # Extract and print the CSV names
        while IFS= read -r csv_info; do
            postgres_csv=$(echo "$csv_info" | awk '{print $1}')
            echo "Current CSV is $postgres_csv"
        done <<< "$csv_list"
    fi
    phase=$($KUBE_CLI get csv "$postgres_csv" -n "$namespace" -o json | jq -r '.status.phase')
    if [[ "$phase" == "Succeeded" ]]; then
        echo "Postgres Operator installation is Succeeded."
        break
    else
        echo "Postgres Operator installation is still $phase. Waiting..."
        sleep 5  # Adjust the sleep time as needed
    fi
done
