#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Create Azure storage account for Quay registry
# Required environment variables:
# - ARO_RESOURCE_GROUP: Azure resource group name
# - ARO_CLUSTER_NAME: ARO cluster name  
# - ARO_LOCATION: Azure location (defaults to northeurope)

usage() {
    echo "Usage: $0"
    echo "Creates Azure storage account for Quay registry"
    echo ""
    echo "Required environment variables:"
    echo "  ARO_RESOURCE_GROUP  - Azure resource group name"
    echo "  ARO_CLUSTER_NAME    - ARO cluster name"
    echo "  ARO_LOCATION        - Azure location (optional, defaults to northeurope)"
    exit 1
}

validate_requirements() {
    local missing_vars=()
    
    if [[ -z "${ARO_RESOURCE_GROUP:-}" ]]; then
        missing_vars+=("ARO_RESOURCE_GROUP")
    fi
    
    if [[ -z "${ARO_CLUSTER_NAME:-}" ]]; then
        missing_vars+=("ARO_CLUSTER_NAME")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables: ${missing_vars[*]}" >&2
        usage
    fi
    
    # Set default location if not provided
    ARO_LOCATION="${ARO_LOCATION:-northeurope}"
    
    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        echo "❌ Azure CLI not found. Please install Azure CLI." >&2
        exit 1
    fi
}

create_storage_account() {
    echo "🏗️ Creating Azure storage account for Quay registry..."
    
    # Generate unique storage account name using cluster hash
    local cluster_hash
    cluster_hash=$(echo "${ARO_CLUSTER_NAME}" | sha256sum | cut -c1-8)
    local timestamp
    timestamp=$(date +%s | tail -c 6)
    local storage_account_name="quay${cluster_hash}${timestamp}"
    
    echo "Storage account name: ${storage_account_name} (for cluster: ${ARO_CLUSTER_NAME})"
    
    # Create storage account
    if az storage account create \
        --name "${storage_account_name}" \
        --resource-group "${ARO_RESOURCE_GROUP}" \
        --location "${ARO_LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=quay cluster="${ARO_CLUSTER_NAME}" team=sap-edge; then
        echo "✅ Storage account created successfully"
    else
        echo "❌ Failed to create storage account" >&2
        exit 1
    fi
    
    # Get storage account key
    echo "🔑 Getting storage account key..."
    local storage_key
    storage_key=$(az storage account keys list \
        --resource-group "${ARO_RESOURCE_GROUP}" \
        --account-name "${storage_account_name}" \
        --query "[0].value" -o tsv)
    
    if [[ -z "${storage_key}" ]]; then
        echo "❌ Failed to get storage account key" >&2
        exit 1
    fi
    
    # Create storage container
    echo "📦 Creating storage container..."
    if az storage container create \
        --name "quay-registry" \
        --account-name "${storage_account_name}" \
        --account-key "${storage_key}"; then
        echo "✅ Storage container created successfully"
    else
        echo "❌ Failed to create storage container" >&2
        exit 1
    fi
    
    # Output configuration information
    echo ""
    echo "✅ Azure storage created successfully!"
    echo "📋 Storage Configuration:"
    echo "   Account Name: ${storage_account_name}"
    echo "   Container: quay-registry"
    echo "   Resource Group: ${ARO_RESOURCE_GROUP}"
    echo ""
    echo "🔑 Set these environment variables for Quay deployment:"
    echo "   export AZURE_STORAGE_ACCOUNT_NAME=${storage_account_name}"
    echo "   export AZURE_STORAGE_ACCOUNT_KEY=${storage_key}"
    echo "   export AZURE_STORAGE_CONTAINER=quay-registry"
}

main() {
    validate_requirements
    create_storage_account
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi