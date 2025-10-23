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

    # Use provided storage account name or generate deterministic one using cluster hash
    local storage_account_name
    if [[ -n "${AZURE_STORAGE_ACCOUNT_NAME:-}" ]]; then
        storage_account_name="${AZURE_STORAGE_ACCOUNT_NAME}"
        echo "Storage account name: ${storage_account_name} (provided via AZURE_STORAGE_ACCOUNT_NAME)"
    else
        # Check for sha256sum availability
        if ! command -v sha256sum >/dev/null 2>&1; then
            echo "❌ Error: sha256sum command not found. Please install coreutils or set AZURE_STORAGE_ACCOUNT_NAME manually." >&2
            exit 1
        fi

        local cluster_hash
        cluster_hash=$(echo "${ARO_CLUSTER_NAME}" | sha256sum | cut -c1-16)
        storage_account_name="quay${cluster_hash}"
        echo "Storage account name: ${storage_account_name} (generated for cluster: ${ARO_CLUSTER_NAME})"
    fi
    
    # Check if storage account already exists
    echo "🔍 Checking if storage account already exists..."
    if az storage account show --name "${storage_account_name}" --resource-group "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1; then
        echo "✅ Storage account already exists: ${storage_account_name}"
        echo "ℹ️  Reusing existing storage account for cluster: ${ARO_CLUSTER_NAME}"
    else
        echo "📦 Creating new storage account..."
        if az storage account create \
            --name "${storage_account_name}" \
            --resource-group "${ARO_RESOURCE_GROUP}" \
            --location "${ARO_LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --tags "${AZURE_TAGS_QUAY:-purpose=quay cluster=${ARO_CLUSTER_NAME} team=sap-edge}"; then
            echo "✅ Storage account created successfully"
        else
            echo "❌ Failed to create storage account" >&2
            exit 1
        fi
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
    
    # Create storage container (idempotent)
    local container_name="${AZURE_STORAGE_CONTAINER:-quay-registry}"
    echo "📦 Creating storage container..."
    echo "🔍 Checking if container '${container_name}' already exists..."
    if az storage container show \
        --name "${container_name}" \
        --account-name "${storage_account_name}" \
        --account-key "${storage_key}" >/dev/null 2>&1; then
        echo "✅ Storage container already exists: ${container_name}"
        echo "ℹ️  Reusing existing container"
    else
        echo "📦 Creating new storage container..."
        if az storage container create \
            --name "${container_name}" \
            --account-name "${storage_account_name}" \
            --account-key "${storage_key}"; then
            echo "✅ Storage container created successfully"
        else
            echo "❌ Failed to create storage container" >&2
            exit 1
        fi
    fi
    
    # Output configuration information
    echo ""
    echo "✅ Azure storage is ready!"
    echo "📋 Storage Configuration:"
    echo "   Account Name: ${storage_account_name}"
    echo "   Container: ${container_name}"
    echo "   Resource Group: ${ARO_RESOURCE_GROUP}"
    echo "   Cluster: ${ARO_CLUSTER_NAME}"
    echo ""
    echo "🔑 Environment variables for Quay deployment:"
    echo "   export AZURE_STORAGE_ACCOUNT_NAME=${storage_account_name}"
    echo "   export AZURE_STORAGE_ACCOUNT_KEY=<use command below to retrieve>"
    echo "   export AZURE_STORAGE_CONTAINER=${container_name}"
    echo ""
    echo "🔐 To securely retrieve the storage key:"
    echo "   az storage account keys list --resource-group \"${ARO_RESOURCE_GROUP}\" --account-name \"${storage_account_name}\" --query '[0].value' -o tsv"
    echo ""
    echo "♻️  Note: This storage account will be reused for future deployments of cluster '${ARO_CLUSTER_NAME}'"
}

main() {
    validate_requirements
    create_storage_account
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi