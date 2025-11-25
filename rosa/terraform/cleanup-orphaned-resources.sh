#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# cleanup-orphaned-resources.sh
# Script to clean up orphaned AWS resources when Terraform state is out of sync

set -e

CLUSTER_NAME=${1:-"sap-eic-rosa"}
AWS_REGION=${2:-"eu-north-1"}
DRY_RUN=${3:-"false"}

echo "🧹 Cleaning up orphaned resources for cluster: $CLUSTER_NAME in region: $AWS_REGION"
echo "   Dry run mode: $DRY_RUN"
echo ""

# Function to execute or echo command based on dry run mode
execute_or_echo() {
    local cmd="$1"
    local description="$2"

    echo "🔍 Checking: $description"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "   [DRY RUN] Would execute: $cmd"
    else
        echo "   Executing: $cmd"
        if eval "$cmd 2>/dev/null"; then
            echo "   ✅ Success: $description"
        else
            echo "   ⚠️  Not found or already deleted: $description"
        fi
    fi
    echo ""
}

# Clean ElastiCache subnet group
execute_or_echo \
    "aws elasticache delete-cache-subnet-group --cache-subnet-group-name '$CLUSTER_NAME-redis-subnet-group' --region '$AWS_REGION'" \
    "ElastiCache subnet group deletion"

# Clean S3 bucket (with all versions)
execute_or_echo \
    "aws s3 rm 's3://$CLUSTER_NAME-quay-registry' --recursive --region '$AWS_REGION'" \
    "S3 bucket object cleanup"

execute_or_echo \
    "aws s3api delete-objects --bucket '$CLUSTER_NAME-quay-registry' --delete \"\$(aws s3api list-object-versions --bucket '$CLUSTER_NAME-quay-registry' --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)\"" \
    "S3 bucket version cleanup"

execute_or_echo \
    "aws s3api delete-objects --bucket '$CLUSTER_NAME-quay-registry' --delete \"\$(aws s3api list-object-versions --bucket '$CLUSTER_NAME-quay-registry' --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null)\"" \
    "S3 bucket delete markers cleanup"

execute_or_echo \
    "aws s3api delete-bucket --bucket '$CLUSTER_NAME-quay-registry' --region '$AWS_REGION'" \
    "S3 bucket deletion"

# Clean RDS PostgreSQL
execute_or_echo \
    "aws rds delete-db-instance --db-instance-identifier '$CLUSTER_NAME-postgres' --skip-final-snapshot --region '$AWS_REGION'" \
    "RDS PostgreSQL deletion"

# Clean DB subnet group
execute_or_echo \
    "aws rds delete-db-subnet-group --db-subnet-group-name '$CLUSTER_NAME-postgres-subnet-group' --region '$AWS_REGION'" \
    "RDS DB subnet group deletion"

# Clean IAM resources (Quay user - NOT ROSA roles)
execute_or_echo \
    "aws iam delete-user-policy --user-name '$CLUSTER_NAME-quay-s3-user' --policy-name '$CLUSTER_NAME-quay-s3-access'" \
    "Quay IAM user policy deletion"

execute_or_echo \
    "aws iam delete-access-key --user-name '$CLUSTER_NAME-quay-s3-user' --access-key-id \"\$(aws iam list-access-keys --user-name '$CLUSTER_NAME-quay-s3-user' --query 'AccessKeyMetadata[0].AccessKeyId' --output text 2>/dev/null)\"" \
    "Quay IAM access key deletion"

execute_or_echo \
    "aws iam delete-user --user-name '$CLUSTER_NAME-quay-s3-user'" \
    "Quay IAM user deletion"

# Clean Security Groups
execute_or_echo \
    "aws ec2 delete-security-group --group-name '$CLUSTER_NAME-postgres-sg' --region '$AWS_REGION'" \
    "PostgreSQL security group deletion"

execute_or_echo \
    "aws ec2 delete-security-group --group-name '$CLUSTER_NAME-redis-sg' --region '$AWS_REGION'" \
    "Redis security group deletion"

echo "🎉 Cleanup completed!"
echo ""
echo "Note: ROSA IAM roles are intentionally left alone as they are managed by the ROSA service."
echo "      These include:"
echo "      - $CLUSTER_NAME-HCP-ROSA-Worker-Role"
echo "      - $CLUSTER_NAME-HCP-ROSA-Installer-Role"
echo "      - $CLUSTER_NAME-HCP-ROSA-Support-Role"
echo ""
echo "Usage examples:"
echo "  # Dry run (default):"
echo "  ./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 true"
echo ""
echo "  # Actually execute cleanup:"
echo "  ./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false"