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
NAMESPACE="sap-eic-external-redis"
CLUSTER_NAME="rec"
POD_NAME="rec-0"

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Wait for RedisEnterpriseCluster to reach Running state.

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

cluster_name="$CLUSTER_NAME"
pod_name="$POD_NAME"
namespace="$NAMESPACE"

# Loop until state equals "Running" and pod is running
while true; do
    cluster_state=$($KUBE_CLI get RedisEnterpriseCluster "$cluster_name" -n "$namespace" -o json | jq -r '.status.state')
    pod_status=$($KUBE_CLI get pod "$pod_name" -n "$namespace" -o json | jq -r '.status.phase')

    if [[ "$cluster_state" == "Running" || "$pod_status" == "Running" ]]; then
        sleep 30 # Let admission webhook to be ready to work with database creation
        echo "Redis Enterprise Cluster State is Running or Pod $pod_name is running. Exiting loop."
        break
    else
        echo "Redis Enterprise Cluster State is $cluster_state and $pod_name is $pod_status. Waiting..."
        sleep 5  # Adjust the sleep time as needed
    fi
done
