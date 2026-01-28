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
NAMESPACE="sap-eic-external-postgres"
CLUSTER_NAME="eic"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for PostgresCluster to be deleted.

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

# Loop until the PostgreSQL cluster is deleted
while true; do
    # Check if the PostgreSQL cluster still exists
    cluster_exists=$($KUBE_CLI get postgrescluster "$cluster_name" -n "$namespace" &>/dev/null; echo $?)

    if [[ "$cluster_exists" != 0 ]]; then
        echo "Postgres Cluster $cluster_name is deleted. Exiting loop."
        break
    else
        echo "Postgres Cluster $cluster_name still exists. Waiting..."
        sleep 5  # Adjust the sleep time as needed
    fi
done
