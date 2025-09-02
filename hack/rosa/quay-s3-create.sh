#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Create S3 bucket for ROSA Quay registry
# Required environment variables:
# - CLUSTER_NAME: ROSA cluster name
# - AWS_REGION: AWS region for S3 bucket (optional, defaults to us-east-1)
# - AWS_ACCESS_KEY_ID: AWS access key
# - AWS_SECRET_ACCESS_KEY: AWS secret key

usage() {
    echo "Usage: $0"
    echo "Creates S3 bucket for ROSA Quay registry"
    echo ""
    echo "Required environment variables:"
    echo "  CLUSTER_NAME           - ROSA cluster name"
    echo "  AWS_ACCESS_KEY_ID      - AWS access key"
    echo "  AWS_SECRET_ACCESS_KEY  - AWS secret access key"
    echo "  AWS_REGION             - AWS region (optional, defaults to us-east-1)"
    exit 1
}

validate_requirements() {
    local missing_vars=()
    
    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        missing_vars+=("CLUSTER_NAME")
    fi
    
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        missing_vars+=("AWS_ACCESS_KEY_ID")
    fi
    
    if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Missing required environment variables: ${missing_vars[*]}" >&2
        usage
    fi
    
    # Set default region if not provided
    AWS_REGION="${AWS_REGION:-us-east-1}"
    export AWS_REGION
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        echo "❌ AWS CLI not found. Please install AWS CLI." >&2
        exit 1
    fi
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "❌ AWS credentials not valid or not configured." >&2
        echo "💡 Make sure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set correctly." >&2
        exit 1
    fi
}

create_s3_bucket() {
    echo "🪣 Creating S3 bucket for ROSA Quay registry..."
    
    # Generate deterministic bucket name using cluster hash
    local cluster_hash
    cluster_hash=$(echo "${CLUSTER_NAME}" | sha256sum | cut -c1-12)
    local bucket_name="rosa-quay-${cluster_hash}"
    
    echo "S3 bucket name: ${bucket_name} (for cluster: ${CLUSTER_NAME})"
    echo "AWS region: ${AWS_REGION}"
    
    # Check if bucket already exists
    echo "🔍 Checking if S3 bucket already exists..."
    if aws s3api head-bucket --bucket "${bucket_name}" 2>/dev/null; then
        echo "✅ S3 bucket already exists: ${bucket_name}"
        echo "ℹ️  Reusing existing bucket for cluster: ${CLUSTER_NAME}"
    else
        echo "📦 Creating new S3 bucket..."
        
        # Create bucket with region-specific configuration
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            # us-east-1 doesn't need LocationConstraint
            if aws s3api create-bucket \
                --bucket "${bucket_name}" \
                --region "${AWS_REGION}"; then
                echo "✅ S3 bucket created successfully"
            else
                echo "❌ Failed to create S3 bucket" >&2
                exit 1
            fi
        else
            # Other regions need LocationConstraint
            if aws s3api create-bucket \
                --bucket "${bucket_name}" \
                --region "${AWS_REGION}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"; then
                echo "✅ S3 bucket created successfully"
            else
                echo "❌ Failed to create S3 bucket" >&2
                exit 1
            fi
        fi
        
        # Wait for bucket to be available
        echo "⏳ Waiting for bucket to be available..."
        aws s3api wait bucket-exists --bucket "${bucket_name}"
    fi
    
    # Configure bucket versioning (recommended for Quay)
    echo "🔧 Configuring bucket versioning..."
    aws s3api put-bucket-versioning \
        --bucket "${bucket_name}" \
        --versioning-configuration Status=Enabled
    
    # Add tags to bucket
    echo "🏷️  Adding tags to bucket..."
    aws s3api put-bucket-tagging \
        --bucket "${bucket_name}" \
        --tagging 'TagSet=[
            {Key=purpose,Value=quay},
            {Key=cluster,Value='${CLUSTER_NAME}'},
            {Key=team,Value=sap-edge},
            {Key=platform,Value=rosa}
        ]'
    
    # Output configuration information
    echo ""
    echo "✅ S3 bucket is ready!"
    echo "📋 S3 Configuration:"
    echo "   Bucket Name: ${bucket_name}"
    echo "   Region: ${AWS_REGION}"
    echo "   Cluster: ${CLUSTER_NAME}"
    echo "   S3 Host: s3.${AWS_REGION}.amazonaws.com"
    echo ""
    echo "🔑 Environment variables for ROSA Quay deployment:"
    echo "   export S3_BUCKET_NAME=${bucket_name}"
    echo "   export S3_REGION=${AWS_REGION}"
    echo "   export S3_HOST=s3.${AWS_REGION}.amazonaws.com"
    echo "   export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
    echo "   export AWS_SECRET_ACCESS_KEY=***hidden***"
    echo ""
    echo "♻️  Note: This S3 bucket will be reused for future deployments of cluster '${CLUSTER_NAME}'"
}

main() {
    validate_requirements
    create_s3_bucket
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi