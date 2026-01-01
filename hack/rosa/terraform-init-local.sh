#!/bin/bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# Helper script to initialize Terraform locally with S3 backend for ROSA

set -e

echo "🚀 ROSA Terraform Local Initialization Helper"
echo "=============================================="
echo ""

# Configuration
BACKEND_BUCKET="eic-test-rosa-terraform-state"
BACKEND_REGION="eu-north-1"
BACKEND_DYNAMODB_TABLE="eic-test-rosa-terraform-state-lock"

# Get cluster name
if [[ -z "${CLUSTER_NAME}" ]]; then
  read -rp "Enter cluster name (default: sap-eic-rosa): " INPUT_CLUSTER_NAME
  CLUSTER_NAME="${INPUT_CLUSTER_NAME:-sap-eic-rosa}"
fi

BACKEND_KEY="rosa/${CLUSTER_NAME}/terraform.tfstate"

echo "📋 Configuration:"
echo "  S3 Bucket: ${BACKEND_BUCKET}"
echo "  S3 Key: ${BACKEND_KEY}"
echo "  Region: ${BACKEND_REGION}"
echo "  DynamoDB Table: ${BACKEND_DYNAMODB_TABLE}"
echo ""

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if [[ -z "${AWS_ACCESS_KEY_ID}" ]]; then
  read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID
  export AWS_ACCESS_KEY_ID
fi

if [[ -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
  read -rsp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
  echo ""
  export AWS_SECRET_ACCESS_KEY
fi

if [[ -z "${AWS_DEFAULT_REGION}" ]]; then
  export AWS_DEFAULT_REGION="${BACKEND_REGION}"
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  echo "❌ AWS credentials are invalid or not set correctly"
  exit 1
fi

echo "✅ AWS credentials verified"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
echo "  Account: ${AWS_ACCOUNT}"
echo "  User: ${AWS_USER}"
echo ""

# Check Red Hat OCM Token
echo "🔐 Checking Red Hat OCM token..."
if [[ -z "${TF_VAR_redhat_ocm_token}" ]]; then
  echo "ℹ️  Red Hat OCM token not set (required for terraform plan/apply)"
  read -rp "Enter Red Hat OCM token (or press Enter to skip): " REDHAT_TOKEN
  if [[ -n "${REDHAT_TOKEN}" ]]; then
    export TF_VAR_redhat_ocm_token="${REDHAT_TOKEN}"
    echo "✅ Red Hat OCM token set"
  else
    echo "⚠️  Skipping Red Hat OCM token (read-only operations only)"
  fi
else
  echo "✅ Red Hat OCM token already set"
fi
echo ""

# Navigate to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../../rosa/terraform"

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
  echo "❌ Terraform directory not found: ${TERRAFORM_DIR}"
  exit 1
fi

cd "${TERRAFORM_DIR}"
echo "📂 Changed to terraform directory: $(pwd)"
echo ""

# Initialize Terraform with S3 backend
echo "🔧 Initializing Terraform with S3 backend..."
terraform init \
  -backend-config="bucket=${BACKEND_BUCKET}" \
  -backend-config="key=${BACKEND_KEY}" \
  -backend-config="region=${BACKEND_REGION}" \
  -backend-config="dynamodb_table=${BACKEND_DYNAMODB_TABLE}" \
  -backend-config="encrypt=true"

echo ""
echo "✅ Terraform initialized successfully!"
echo ""

# Verify state access
echo "🔍 Verifying state file access..."
if terraform state list &>/dev/null; then
  RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
  echo "✅ State file accessible"
  echo "  Resources in state: ${RESOURCE_COUNT}"
  echo ""
  
  if [[ ${RESOURCE_COUNT} -gt 0 ]]; then
    echo "📊 Resources in state:"
    terraform state list | head -10
    if [[ ${RESOURCE_COUNT} -gt 10 ]]; then
      echo "  ... and $((RESOURCE_COUNT - 10)) more"
    fi
  else
    echo "ℹ️  State file exists but is empty (no resources deployed yet)"
  fi
else
  echo "⚠️  Could not access state file (may be empty or not yet created)"
fi

echo ""
echo "=============================================="
echo "🎉 Setup Complete!"
echo ""
echo "You can now run Terraform commands:"
echo "  terraform show           # View current state"
echo "  terraform state list     # List all resources"
echo "  terraform output         # Get outputs"
echo "  terraform plan           # Preview changes"
echo "  terraform apply          # Apply changes (⚠️  careful!)"
echo ""
echo "💡 Tips:"
echo "  - Read-only commands (show, state, output, plan) are always safe"
echo "  - Before apply/destroy, coordinate with your team"
echo "  - DynamoDB locking prevents concurrent modifications"
echo ""
echo "🔒 Current working directory: $(pwd)"
echo "📝 State location: s3://${BACKEND_BUCKET}/${BACKEND_KEY}"
echo ""

