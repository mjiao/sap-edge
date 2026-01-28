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
CLUSTER_NAME="eic"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for PostgresCluster to be ready.

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

cluster_name="$CLUSTER_NAME"
namespace="$NAMESPACE"

# Loop until readyReplicas equals 1
while true; do
    ready_replicas=$($KUBE_CLI get postgrescluster "$cluster_name" -o json -n "$namespace" | jq -r '.status.instances[0].readyReplicas')

    if [[ "$ready_replicas" == "1" ]]; then
        echo "Crunchy Postgres is ready. Exiting loop."
        break
    else
        echo "Crunchy Postgres readyReplicas is $ready_replicas. Waiting..."
        sleep 5  # Adjust the sleep time as needed
    fi
done
