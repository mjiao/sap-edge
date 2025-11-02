#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Get Azure storage account credentials for Quay registry
# Storage is created by Bicep deployment (bicep/azure-services.bicep)
# This script retrieves the credentials from the Bicep deployment outputs
#
# Required environment variables:
# - ARO_RESOURCE_GROUP: Azure resource group name

usage() {
    echo "Usage: $0"
    echo "Retrieves Azure storage credentials for Quay registry"
    echo ""
    echo "Required environment variables:"
    echo "  ARO_RESOURCE_GROUP  - Azure resource group name"
    echo ""
    echo "NOTE: Storage must be created first by running:"
    echo "  make aro-deploy-test"
    exit 1
}

validate_requirements() {
    local missing_vars=()
    
    if [[ -z "${ARO_RESOURCE_GROUP:-}" ]]; then
        missing_vars+=("ARO_RESOURCE_GROUP")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables: ${missing_vars[*]}" >&2
        usage
    fi
    
    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        echo "❌ Azure CLI not found. Please install Azure CLI." >&2
        exit 1
    fi
}

get_storage_credentials() {
    echo "🔍 Retrieving Azure storage credentials from Bicep deployment..."
    echo ""
    
    # Try to get from Bicep deployment outputs
    local deployment_name="azure-services-deployment"
    
    if ! az deployment group show \
        --name "${deployment_name}" \
        --resource-group "${ARO_RESOURCE_GROUP}" >/dev/null 2>&1; then
        echo "❌ Bicep deployment '${deployment_name}' not found in resource group '${ARO_RESOURCE_GROUP}'" >&2
        echo "💡 Storage must be created first by running: make aro-deploy-test" >&2
        exit 1
    fi
    
    # Get storage account name from Bicep outputs
    local storage_account_name
    storage_account_name=$(az deployment group show \
        --name "${deployment_name}" \
        --resource-group "${ARO_RESOURCE_GROUP}" \
        --query 'properties.outputs.quayStorageAccountName.value' \
        -o tsv)
    
    if [[ -z "${storage_account_name}" ]] || [[ "${storage_account_name}" == "null" ]]; then
        echo "❌ Quay storage not deployed. Please set deployQuay=true in Bicep parameters." >&2
        exit 1
    fi
    
    # Get storage account key (retrieved to validate it exists, but not exported for security)
    # shellcheck disable=SC2034
    local storage_key=$(az deployment group show \
        --name "${deployment_name}" \
        --resource-group "${ARO_RESOURCE_GROUP}" \
        --query 'properties.outputs.quayStorageAccountKey.value' \
        -o tsv)
    
    # Get container name
    local container_name
    container_name=$(az deployment group show \
        --name "${deployment_name}" \
        --resource-group "${ARO_RESOURCE_GROUP}" \
        --query 'properties.outputs.quayContainerName.value' \
        -o tsv)
    
    if [[ -z "${container_name}" ]]; then
        container_name="quay-registry"
    fi
    
    # Output configuration information
    echo "✅ Azure storage credentials retrieved!"
    echo "📋 Storage Configuration:"
    echo "   Account Name: ${storage_account_name}"
    echo "   Container: ${container_name}"
    echo "   Resource Group: ${ARO_RESOURCE_GROUP}"
    echo ""
    echo "🔑 Environment variables for Quay deployment:"
    echo "   export AZURE_STORAGE_ACCOUNT_NAME=${storage_account_name}"
    echo "   export AZURE_STORAGE_ACCOUNT_KEY='<hidden>'"
    echo "   export AZURE_STORAGE_CONTAINER=${container_name}"
    echo ""
    echo "📝 To use with Ansible Quay deployment:"
    echo "   export AZURE_STORAGE_ACCOUNT_NAME=${storage_account_name}"
    echo "   export AZURE_STORAGE_ACCOUNT_KEY=\$(az deployment group show --name ${deployment_name} --resource-group ${ARO_RESOURCE_GROUP} --query 'properties.outputs.quayStorageAccountKey.value' -o tsv)"
    echo "   export AZURE_STORAGE_CONTAINER=${container_name}"
    echo "   make aro-quay-deploy"
}

main() {
    validate_requirements
    get_storage_credentials
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
