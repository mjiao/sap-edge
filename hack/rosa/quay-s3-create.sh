#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Get S3 bucket credentials for ROSA Quay registry
# S3 bucket is created by Terraform deployment (rosa/terraform/aws-services.tf)
# This script retrieves the credentials from Terraform outputs
#
# Required: Must be run from rosa/terraform directory or TERRAFORM_DIR must be set

usage() {
    echo "Usage: $0"
    echo "Retrieves S3 bucket credentials for ROSA Quay registry"
    echo ""
    echo "Must be run from rosa/terraform directory, or set TERRAFORM_DIR"
    echo ""
    echo "NOTE: S3 bucket must be created first by running:"
    echo "  cd rosa/terraform && terraform apply"
    exit 1
}

validate_requirements() {
    # Check if Terraform CLI is available
    if ! command -v terraform >/dev/null 2>&1; then
        echo "❌ Terraform CLI not found. Please install Terraform." >&2
        exit 1
    fi
    
    # Determine Terraform directory
    if [[ -n "${TERRAFORM_DIR:-}" ]]; then
        cd "${TERRAFORM_DIR}" || {
            echo "❌ Cannot change to TERRAFORM_DIR: ${TERRAFORM_DIR}" >&2
            exit 1
        }
    elif [[ -f "terraform.tfstate" ]] || [[ -f ".terraform/terraform.tfstate" ]]; then
        echo "✅ Found Terraform state in current directory"
    else
        echo "❌ Not in Terraform directory. Please run from rosa/terraform/ or set TERRAFORM_DIR." >&2
        usage
    fi
}

get_s3_credentials() {
    echo "🔍 Retrieving S3 credentials from Terraform outputs..."
    echo ""
    
    # Check if Terraform has been initialized and applied
    if ! terraform output >/dev/null 2>&1; then
        echo "❌ Terraform outputs not available. Please run 'terraform apply' first." >&2
        exit 1
    fi
    
    # Get S3 bucket name
    local bucket_name
    bucket_name=$(terraform output -raw quay_s3_bucket_name 2>/dev/null)
    
    if [[ -z "${bucket_name}" ]] || [[ "${bucket_name}" == "null" ]]; then
        echo "❌ Quay S3 bucket not deployed. Please set deploy_quay=true in terraform.tfvars." >&2
        exit 1
    fi
    
    # Get S3 bucket region
    local bucket_region
    bucket_region=$(terraform output -raw quay_s3_bucket_region 2>/dev/null)
    
    # Get IAM access key ID
    local access_key_id
    access_key_id=$(terraform output -raw quay_s3_access_key_id 2>/dev/null)
    
    # Get IAM secret access key (retrieved to validate it exists, but not exported for security)
    # shellcheck disable=SC2034
    local secret_access_key=$(terraform output -raw quay_s3_secret_access_key 2>/dev/null)
    
    # Construct S3 host
    local s3_host="s3.${bucket_region}.amazonaws.com"
    
    # Output configuration information
    echo "✅ S3 credentials retrieved!"
    echo "📋 S3 Configuration:"
    echo "   Bucket Name: ${bucket_name}"
    echo "   Region: ${bucket_region}"
    echo "   S3 Host: ${s3_host}"
    echo ""
    echo "🔑 Environment variables for Quay deployment:"
    echo "   export S3_BUCKET_NAME=${bucket_name}"
    echo "   export S3_REGION=${bucket_region}"
    echo "   export S3_HOST=${s3_host}"
    echo "   export AWS_ACCESS_KEY_ID=${access_key_id}"
    echo "   export AWS_SECRET_ACCESS_KEY='<hidden>'"
    echo ""
    echo "📝 To use with Ansible Quay deployment:"
    echo "   export S3_BUCKET_NAME=${bucket_name}"
    echo "   export S3_REGION=${bucket_region}"
    echo "   export S3_HOST=${s3_host}"
    echo "   export AWS_ACCESS_KEY_ID=${access_key_id}"
    echo "   export AWS_SECRET_ACCESS_KEY=\$(cd rosa/terraform && terraform output -raw quay_s3_secret_access_key)"
    echo "   make rosa-quay-deploy"
}

main() {
    validate_requirements
    get_s3_credentials
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
