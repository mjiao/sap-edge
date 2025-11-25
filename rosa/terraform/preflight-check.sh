#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# preflight-check.sh
# Pre-deployment check to detect resource conflicts that would cause Terraform failures

set -e

CLUSTER_NAME=${1:-"sap-eic-rosa"}
AWS_REGION=${2:-"eu-north-1"}

echo "🔍 Pre-flight check for resource conflicts - Cluster: $CLUSTER_NAME"
echo ""

CONFLICTS=0

# Function to check if resource exists
check_resource() {
    local resource_type="$1"
    local check_command="$2"
    local resource_name="$3"

    if eval "$check_command" &>/dev/null; then
        echo "❌ $resource_type already exists: $resource_name"
        CONFLICTS=$((CONFLICTS+1))
    else
        echo "✅ $resource_type available: $resource_name"
    fi
}

# Check ElastiCache resources
check_resource \
    "ElastiCache Subnet Group" \
    "aws elasticache describe-cache-subnet-groups --cache-subnet-group-name '$CLUSTER_NAME-redis-subnet-group' --region '$AWS_REGION'" \
    "$CLUSTER_NAME-redis-subnet-group"

check_resource \
    "ElastiCache Replication Group" \
    "aws elasticache describe-replication-groups --replication-group-id '$CLUSTER_NAME-redis' --region '$AWS_REGION'" \
    "$CLUSTER_NAME-redis"

# Check S3 bucket
check_resource \
    "S3 Bucket" \
    "aws s3api head-bucket --bucket '$CLUSTER_NAME-quay-registry' --region '$AWS_REGION'" \
    "$CLUSTER_NAME-quay-registry"

# Check RDS resources
check_resource \
    "RDS Instance" \
    "aws rds describe-db-instances --db-instance-identifier '$CLUSTER_NAME-postgres' --region '$AWS_REGION'" \
    "$CLUSTER_NAME-postgres"

check_resource \
    "RDS Subnet Group" \
    "aws rds describe-db-subnet-groups --db-subnet-group-name '$CLUSTER_NAME-postgres-subnet-group' --region '$AWS_REGION'" \
    "$CLUSTER_NAME-postgres-subnet-group"

# Check IAM resources (Quay user)
check_resource \
    "IAM User (Quay)" \
    "aws iam get-user --user-name '$CLUSTER_NAME-quay-s3-user'" \
    "$CLUSTER_NAME-quay-s3-user"

# Check Security Groups (check if any exist with the name)
check_resource \
    "Security Group (PostgreSQL)" \
    "aws ec2 describe-security-groups --filters Name=group-name,Values='$CLUSTER_NAME-postgres-sg' --region '$AWS_REGION' --query 'SecurityGroups[0].GroupId' --output text | grep -v 'None'" \
    "$CLUSTER_NAME-postgres-sg"

check_resource \
    "Security Group (Redis)" \
    "aws ec2 describe-security-groups --filters Name=group-name,Values='$CLUSTER_NAME-redis-sg' --region '$AWS_REGION' --query 'SecurityGroups[0].GroupId' --output text | grep -v 'None'" \
    "$CLUSTER_NAME-redis-sg"

# Check ROSA IAM roles (these are expected to exist, just informational)
echo ""
echo "🔍 ROSA IAM roles status (informational only):"

for role in "HCP-ROSA-Worker-Role" "HCP-ROSA-Installer-Role" "HCP-ROSA-Support-Role"; do
    if aws iam get-role --role-name "$CLUSTER_NAME-$role" &>/dev/null; then
        echo "ℹ️  ROSA Role exists (managed by ROSA): $CLUSTER_NAME-$role"
    else
        echo "ℹ️  ROSA Role missing (will be created by ROSA): $CLUSTER_NAME-$role"
    fi
done

echo ""
echo "📋 Pre-flight check summary:"

if [ $CONFLICTS -gt 0 ]; then
    echo "❌ Found $CONFLICTS resource conflicts that will cause Terraform to fail"
    echo ""
    echo "🔧 To resolve conflicts, you can:"
    echo "   1. Run cleanup script: ./cleanup-orphaned-resources.sh $CLUSTER_NAME $AWS_REGION false"
    echo "   2. Use a different cluster name in your pipeline"
    echo "   3. Import existing resources into Terraform state"
    exit 1
else
    echo "✅ No resource conflicts detected. Terraform deployment should proceed successfully."
    exit 0
fi