#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Deploy Quay registry operator and instance on ROSA with S3 storage
# Required environment variables:
# - CLUSTER_NAME: ROSA cluster name
# - S3_BUCKET_NAME: S3 bucket name for Quay storage
# - S3_REGION: S3 region
# - S3_HOST: S3 host (e.g., s3.us-east-1.amazonaws.com)
# - AWS_ACCESS_KEY_ID: AWS access key
# - AWS_SECRET_ACCESS_KEY: AWS secret key

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    echo "Usage: $0"
    echo "Deploy Quay registry operator and instance on ROSA with S3 storage"
    echo ""
    echo "Required environment variables:"
    echo "  CLUSTER_NAME           - ROSA cluster name"
    echo "  S3_BUCKET_NAME         - S3 bucket name for Quay storage"
    echo "  S3_REGION              - S3 region"
    echo "  S3_HOST                - S3 host endpoint"
    echo "  AWS_ACCESS_KEY_ID      - AWS access key"
    echo "  AWS_SECRET_ACCESS_KEY  - AWS secret key"
    exit 1
}

validate_requirements() {
    local missing_vars=()
    
    for var in CLUSTER_NAME S3_BUCKET_NAME S3_REGION S3_HOST AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
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
        echo "ℹ️  Use 'make rosa-quay-delete' first if you want to redeploy"
        exit 0
    fi
}

deploy_operator() {
    echo "📦 Deploying Quay registry operator on ROSA cluster..."
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
    echo "🔧 Creating Quay configuration with S3 storage..."
    echo "Using S3 bucket: ${S3_BUCKET_NAME}"
    echo "Using S3 region: ${S3_REGION}"
    echo "Using S3 host: ${S3_HOST}"
    
    local temp_config
    temp_config=$(mktemp)
    
    # Use awk for safe variable substitution with S3 configuration
    awk -v s3_host="${S3_HOST}" \
        -v access_key="${AWS_ACCESS_KEY_ID}" \
        -v secret_key="${AWS_SECRET_ACCESS_KEY}" \
        -v bucket_name="${S3_BUCKET_NAME}" \
        -v s3_region="${S3_REGION}" '
        {
            gsub(/\${S3_HOST_PLACEHOLDER}/, s3_host)
            gsub(/\${AWS_ACCESS_KEY_ID_PLACEHOLDER}/, access_key)
            gsub(/\${AWS_SECRET_ACCESS_KEY_PLACEHOLDER}/, secret_key)
            gsub(/\${S3_BUCKET_NAME_PLACEHOLDER}/, bucket_name)
            gsub(/\${S3_REGION_PLACEHOLDER}/, s3_region)
            print
        }' "${PROJECT_ROOT}/edge-integration-cell/quay-registry/rosa-quay-config-secret.yaml" > "${temp_config}"
    
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
    oc apply -f "${PROJECT_ROOT}/edge-integration-cell/quay-registry/rosa-quay-registry.yaml"
    echo "✅ Quay deployment initiated on ROSA"
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