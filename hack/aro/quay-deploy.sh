#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Deploy Quay registry operator and instance on ARO with Azure storage
# Required environment variables:
# - ARO_CLUSTER_NAME: ARO cluster name
# - ARO_RESOURCE_GROUP: Azure resource group name
# - AZURE_STORAGE_ACCOUNT_NAME: Azure storage account name
# - AZURE_STORAGE_ACCOUNT_KEY: Azure storage account key
# - AZURE_STORAGE_CONTAINER: Azure storage container name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    echo "Usage: $0"
    echo "Deploy Quay registry operator and instance on ARO with Azure storage"
    echo ""
    echo "Required environment variables:"
    echo "  ARO_CLUSTER_NAME           - ARO cluster name"
    echo "  ARO_RESOURCE_GROUP         - Azure resource group name"
    echo "  AZURE_STORAGE_ACCOUNT_NAME - Azure storage account name"
    echo "  AZURE_STORAGE_ACCOUNT_KEY  - Azure storage account key"
    echo "  AZURE_STORAGE_CONTAINER    - Azure storage container name"
    exit 1
}

validate_requirements() {
    local missing_vars=()
    
    for var in ARO_CLUSTER_NAME ARO_RESOURCE_GROUP AZURE_STORAGE_ACCOUNT_NAME AZURE_STORAGE_ACCOUNT_KEY AZURE_STORAGE_CONTAINER; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables: ${missing_vars[*]}" >&2
        usage
    fi
    
    # Check if oc CLI is available
    if ! command -v oc >/dev/null 2>&1; then
        echo "❌ OpenShift CLI (oc) not found. Please install oc CLI." >&2
        exit 1
    fi
    
    # Check if we're logged into a cluster
    if ! oc whoami >/dev/null 2>&1; then
        echo "❌ Not logged into OpenShift cluster. Please login first." >&2
        exit 1
    fi
}

check_existing_deployment() {
    echo "🔍 Checking if Quay registry is already deployed..."
    if oc get quayregistry test-registry -n openshift-operators >/dev/null 2>&1; then
        echo "✅ Quay registry already exists, skipping deployment"
        echo "ℹ️  Use 'make aro-quay-delete' first if you want to redeploy"
        exit 0
    fi
}

deploy_operator() {
    echo "📦 Deploying Quay registry operator on ARO cluster..."
    oc apply -f "${PROJECT_ROOT}/edge-integration-cell/quay-registry/quay-operator-subscription.yaml"
    
    echo "⏳ Waiting for Quay operator to be ready..."
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if oc get csv -n openshift-operators | grep -q "quay-operator.*Succeeded"; then
            echo "✅ Quay operator is ready"
            return 0
        fi
        echo "Waiting for operator... (${elapsed}s elapsed)"
        sleep ${interval}
        elapsed=$((elapsed + interval))
    done
    
    echo "❌ Timeout waiting for Quay operator to be ready" >&2
    exit 1
}

create_config_secret() {
    echo "🔧 Creating Quay configuration with Azure storage..."
    echo "Using storage account: ${AZURE_STORAGE_ACCOUNT_NAME}"
    echo "Using container: ${AZURE_STORAGE_CONTAINER}"
    echo "Storage key length: ${#AZURE_STORAGE_ACCOUNT_KEY} characters"
    
    local temp_config
    temp_config=$(mktemp)
    
    # Use a safer approach with awk to avoid sed delimiter issues
    awk -v account_name="${AZURE_STORAGE_ACCOUNT_NAME}" \
        -v account_key="${AZURE_STORAGE_ACCOUNT_KEY}" \
        -v container="${AZURE_STORAGE_CONTAINER}" '
        {
            gsub(/\${AZURE_STORAGE_ACCOUNT_NAME_PLACEHOLDER}/, account_name)
            gsub(/\${AZURE_STORAGE_ACCOUNT_KEY_PLACEHOLDER}/, account_key)
            gsub(/\${AZURE_STORAGE_CONTAINER_PLACEHOLDER}/, container)
            print
        }' "${PROJECT_ROOT}/edge-integration-cell/quay-registry/aro-quay-config-secret.yaml" > "${temp_config}"
    
    echo "🔍 Template substitution completed, checking result..."
    if grep -q "PLACEHOLDER" "${temp_config}"; then
        echo "❌ Warning: Template still contains placeholders:"
        grep "PLACEHOLDER" "${temp_config}" || true
    else
        echo "✅ Template substitution successful"
    fi
    
    echo "🔍 Applying config bundle secret to openshift-operators namespace..."
    oc apply -f "${temp_config}"
    rm -f "${temp_config}"
    
    echo "⏳ Waiting for config bundle secret to be created..."
    local timeout=60
    local elapsed=0
    local interval=5
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if oc get secret config-bundle-secret -n openshift-operators >/dev/null 2>&1; then
            echo "✅ Config bundle secret is ready"
            return 0
        fi
        echo "Waiting for secret... (${elapsed}s elapsed)"
        sleep ${interval}
        elapsed=$((elapsed + interval))
    done
    
    echo "❌ Timeout waiting for config bundle secret" >&2
    exit 1
}

create_quay_registry() {
    echo "🚀 Creating Quay registry instance..."
    oc apply -f "${PROJECT_ROOT}/edge-integration-cell/quay-registry/aro-quay-registry.yaml"
    echo "✅ Quay deployment initiated on ARO"
}

main() {
    validate_requirements
    check_existing_deployment
    deploy_operator
    create_config_secret
    create_quay_registry
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi