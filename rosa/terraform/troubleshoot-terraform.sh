#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# troubleshoot-terraform.sh
# Comprehensive troubleshooting script for Terraform lifecycle issues

set -e

CLUSTER_NAME=${1:-"sap-eic-rosa"}
AWS_REGION=${2:-"eu-north-1"}
ACTION=${3:-"diagnose"}

echo "🔧 Terraform Troubleshooting Tool"
echo "Cluster: $CLUSTER_NAME | Region: $AWS_REGION | Action: $ACTION"
echo "=========================================="

# Function to show terraform state vs AWS reality
show_state_drift() {
    echo ""
    echo "📊 TERRAFORM STATE vs AWS REALITY:"
    echo "-----------------------------------"

    echo "🔍 Terraform State Resources:"
    if terraform state list 2>/dev/null | grep -q .; then
        terraform state list
    else
        echo "   (No resources in Terraform state)"
    fi

    echo ""
    echo "🔍 AWS Resources That Actually Exist:"

    # Check each resource type
    local aws_resources_found=0

    # ElastiCache
    if aws elasticache describe-cache-subnet-groups --cache-subnet-group-name "$CLUSTER_NAME-redis-subnet-group" --region "$AWS_REGION" &>/dev/null; then
        echo "   ✓ ElastiCache Subnet Group: $CLUSTER_NAME-redis-subnet-group"
        aws_resources_found=1
    fi

    if aws elasticache describe-replication-groups --replication-group-id "$CLUSTER_NAME-redis" --region "$AWS_REGION" &>/dev/null; then
        echo "   ✓ ElastiCache Replication Group: $CLUSTER_NAME-redis"
        aws_resources_found=1
    fi

    # S3
    if aws s3api head-bucket --bucket "$CLUSTER_NAME-quay-registry" --region "$AWS_REGION" &>/dev/null; then
        echo "   ✓ S3 Bucket: $CLUSTER_NAME-quay-registry"
        aws_resources_found=1
    fi

    # RDS
    if aws rds describe-db-instances --db-instance-identifier "$CLUSTER_NAME-postgres" --region "$AWS_REGION" &>/dev/null; then
        echo "   ✓ RDS Instance: $CLUSTER_NAME-postgres"
        aws_resources_found=1
    fi

    if aws rds describe-db-subnet-groups --db-subnet-group-name "$CLUSTER_NAME-postgres-subnet-group" --region "$AWS_REGION" &>/dev/null; then
        echo "   ✓ RDS Subnet Group: $CLUSTER_NAME-postgres-subnet-group"
        aws_resources_found=1
    fi

    # Security Groups
    if aws ec2 describe-security-groups --filters Name=group-name,Values="$CLUSTER_NAME-postgres-sg" --region "$AWS_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -v "None" &>/dev/null; then
        echo "   ✓ Security Group (PostgreSQL): $CLUSTER_NAME-postgres-sg"
        aws_resources_found=1
    fi

    if aws ec2 describe-security-groups --filters Name=group-name,Values="$CLUSTER_NAME-redis-sg" --region "$AWS_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -v "None" &>/dev/null; then
        echo "   ✓ Security Group (Redis): $CLUSTER_NAME-redis-sg"
        aws_resources_found=1
    fi

    # IAM
    if aws iam get-user --user-name "$CLUSTER_NAME-quay-s3-user" &>/dev/null; then
        echo "   ✓ IAM User: $CLUSTER_NAME-quay-s3-user"
        aws_resources_found=1
    fi

    if [[ $aws_resources_found -eq 0 ]]; then
        echo "   (No AWS resources found)"
    fi
}

# Function to show detailed resource status
show_detailed_status() {
    echo ""
    echo "🔍 DETAILED RESOURCE STATUS:"
    echo "----------------------------"

    # Check RDS status
    if aws rds describe-db-instances --db-instance-identifier "$CLUSTER_NAME-postgres" --region "$AWS_REGION" &>/dev/null; then
        local rds_status=$(aws rds describe-db-instances --db-instance-identifier "$CLUSTER_NAME-postgres" --region "$AWS_REGION" --query 'DBInstances[0].DBInstanceStatus' --output text)
        echo "   RDS PostgreSQL Status: $rds_status"
    fi

    # Check ElastiCache status
    if aws elasticache describe-replication-groups --replication-group-id "$CLUSTER_NAME-redis" --region "$AWS_REGION" &>/dev/null; then
        local redis_status=$(aws elasticache describe-replication-groups --replication-group-id "$CLUSTER_NAME-redis" --region "$AWS_REGION" --query 'ReplicationGroups[0].Status' --output text 2>/dev/null)
        echo "   ElastiCache Redis Status: $redis_status"
    fi

    # Check if ROSA cluster exists
    echo ""
    echo "🔍 ROSA CLUSTER STATUS:"
    if rosa list clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        local rosa_status=$(rosa describe cluster "$CLUSTER_NAME" --output json 2>/dev/null | jq -r '.status.state // "unknown"' 2>/dev/null || echo "unknown")
        echo "   ROSA Cluster Status: $rosa_status"
    else
        echo "   ROSA Cluster: Not found"
    fi
}

# Function to provide specific recovery steps
suggest_recovery() {
    echo ""
    echo "🛠  RECOVERY SUGGESTIONS:"
    echo "------------------------"

    local has_state=$(terraform state list 2>/dev/null | wc -l)
    local has_aws_resources=0

    # Quick check for AWS resources
    if aws s3api head-bucket --bucket "$CLUSTER_NAME-quay-registry" &>/dev/null ||
       aws rds describe-db-instances --db-instance-identifier "$CLUSTER_NAME-postgres" &>/dev/null ||
       aws elasticache describe-replication-groups --replication-group-id "$CLUSTER_NAME-redis" &>/dev/null; then
        has_aws_resources=1
    fi

    if [[ $has_state -gt 0 && $has_aws_resources -eq 1 ]]; then
        echo "   ✅ SCENARIO: Normal state - resources exist in both Terraform and AWS"
        echo "   💡 Try: terraform plan (should show no changes)"
        echo "   💡 If destroy needed: terraform destroy"

    elif [[ $has_state -eq 0 && $has_aws_resources -eq 1 ]]; then
        echo "   ⚠️  SCENARIO: STATE DRIFT - AWS resources exist but not in Terraform state"
        echo "   💡 Option A: Clean up manually: ./cleanup-orphaned-resources.sh $CLUSTER_NAME $AWS_REGION false"
        echo "   💡 Option B: Import resources: terraform import [resource] [id]"
        echo "   💡 Option C: Use different cluster name"

    elif [[ $has_state -gt 0 && $has_aws_resources -eq 0 ]]; then
        echo "   🔄 SCENARIO: Terraform thinks resources exist but they're gone from AWS"
        echo "   💡 Refresh state: terraform refresh"
        echo "   💡 Then plan: terraform plan"

    elif [[ $has_state -eq 0 && $has_aws_resources -eq 0 ]]; then
        echo "   ✅ SCENARIO: Clean slate - ready for fresh deployment"
        echo "   💡 Proceed with: terraform plan && terraform apply"

    else
        echo "   ❓ SCENARIO: Mixed state - manual investigation needed"
        echo "   💡 Check: terraform plan"
        echo "   💡 Check: ./preflight-check.sh $CLUSTER_NAME $AWS_REGION"
    fi
}

# Main logic
case $ACTION in
    "diagnose"|"check")
        show_state_drift
        show_detailed_status
        suggest_recovery
        ;;
    "clean")
        echo "🧹 Running cleanup sequence..."
        ./cleanup-orphaned-resources.sh "$CLUSTER_NAME" "$AWS_REGION" false
        echo "✅ Cleanup completed"
        ;;
    "reset")
        echo "🔄 Performing complete reset..."
        echo "1. Refreshing Terraform state..."
        terraform refresh || echo "   (Refresh failed - continuing)"
        echo "2. Running cleanup..."
        ./cleanup-orphaned-resources.sh "$CLUSTER_NAME" "$AWS_REGION" false
        echo "3. Final state check..."
        show_state_drift
        echo "✅ Reset completed"
        ;;
    *)
        echo "Usage: $0 [cluster_name] [region] [action]"
        echo ""
        echo "Actions:"
        echo "  diagnose - Show state drift and recovery suggestions (default)"
        echo "  clean    - Clean up orphaned AWS resources"
        echo "  reset    - Full reset (refresh + clean)"
        echo ""
        echo "Examples:"
        echo "  $0 sap-eic-rosa eu-north-1 diagnose"
        echo "  $0 sap-eic-rosa eu-north-1 clean"
        echo "  $0 sap-eic-rosa eu-north-1 reset"
        ;;
esac