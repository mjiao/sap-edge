#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Wrapper script to deploy Quay on ROSA with proper authentication
# This script ensures KUBECONFIG and AWS credentials are properly set
# without exposing them in make logs

echo "🎯 Starting ROSA Quay deployment..."

# Validate required environment variables
: "${CLUSTER_NAME:?CLUSTER_NAME not set}"
: "${S3_BUCKET_NAME:?S3_BUCKET_NAME not set}"
: "${S3_REGION:?S3_REGION not set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${QUAY_ADMIN_PASSWORD:?QUAY_ADMIN_PASSWORD not set}"
: "${QUAY_ADMIN_EMAIL:?QUAY_ADMIN_EMAIL not set}"

# Set S3 host
S3_HOST="${S3_HOST:-s3.${S3_REGION}.amazonaws.com}"
echo "Using S3 host: ${S3_HOST}"

# Ensure KUBECONFIG is set and exported
if [[ -z "${KUBECONFIG:-}" ]]; then
  echo "⚠️  KUBECONFIG not set, using default"
  export KUBECONFIG="/root/.kube/config"
else
  echo "Using kubeconfig: ${KUBECONFIG}"
  export KUBECONFIG
fi

# Verify kubeconfig file exists
if [[ ! -f "${KUBECONFIG}" ]]; then
  echo "❌ Error: Kubeconfig file not found at: ${KUBECONFIG}"
  exit 1
fi

# Export AWS credentials for ansible
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# Run ansible playbook with explicit kubeconfig
ansible-playbook "$(dirname "$0")/quay-deploy.yml" \
  -i "$(dirname "$0")/inventory.yml" \
  -e "platform=rosa" \
  -e "cluster_name=${CLUSTER_NAME}" \
  -e "s3_bucket_name=${S3_BUCKET_NAME}" \
  -e "s3_region=${S3_REGION}" \
  -e "s3_host=${S3_HOST}" \
  -e "quay_admin_password=${QUAY_ADMIN_PASSWORD}" \
  -e "quay_admin_email=${QUAY_ADMIN_EMAIL}" \
  -e "kubeconfig_path=${KUBECONFIG}"

echo "✅ ROSA Quay deployment completed"

