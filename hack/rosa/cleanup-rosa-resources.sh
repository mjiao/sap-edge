#!/bin/bash
# Delete existing ROSA resources

set -e

CLUSTER_NAME="sap-eic-rosa"
AWS_REGION="eu-north-1"

echo "🗑️  Cleaning up ROSA resources..."
echo "=================================="

# 1. Delete ROSA cluster
echo "1️⃣  Deleting ROSA cluster: ${CLUSTER_NAME}"
if rosa describe cluster -c "${CLUSTER_NAME}" &>/dev/null; then
  rosa delete cluster -c "${CLUSTER_NAME}" --yes
  echo "⏳ Waiting for cluster deletion (this takes ~30-45 minutes)..."
  rosa logs uninstall -c "${CLUSTER_NAME}" --watch || true
  echo "✅ Cluster deleted"
else
  echo "ℹ️  Cluster not found or already deleted"
fi

# 2. Find and delete VPC created for ROSA
echo ""
echo "2️⃣  Finding VPC for cluster..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
  --query "Vpcs[0].VpcId" \
  --output text 2>/dev/null || echo "")

if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]]; then
  echo "Found VPC: ${VPC_ID}"
  echo "⚠️  Deleting VPC and associated resources..."
  
  # Delete NAT Gateways
  aws ec2 describe-nat-gateways --region "${AWS_REGION}" --filter "Name=vpc-id,Values=${VPC_ID}" \
    --query "NatGateways[*].NatGatewayId" --output text | xargs -r -n1 aws ec2 delete-nat-gateway --region "${AWS_REGION}" --nat-gateway-id || true
  
  # Delete Internet Gateways
  aws ec2 describe-internet-gateways --region "${AWS_REGION}" --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[*].InternetGatewayId" --output text | xargs -r -n1 -I {} aws ec2 detach-internet-gateway --region "${AWS_REGION}" --internet-gateway-id {} --vpc-id "${VPC_ID}" || true
  aws ec2 describe-internet-gateways --region "${AWS_REGION}" --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[*].InternetGatewayId" --output text | xargs -r -n1 aws ec2 delete-internet-gateway --region "${AWS_REGION}" --internet-gateway-id || true
  
  # Delete Subnets
  aws ec2 describe-subnets --region "${AWS_REGION}" --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].SubnetId" --output text | xargs -r -n1 aws ec2 delete-subnet --region "${AWS_REGION}" --subnet-id || true
  
  # Delete Route Tables (except main)
  aws ec2 describe-route-tables --region "${AWS_REGION}" --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "RouteTables[?Associations[0].Main != \`true\`].RouteTableId" --output text | xargs -r -n1 aws ec2 delete-route-table --region "${AWS_REGION}" --route-table-id || true
  
  # Delete Security Groups (except default)
  aws ec2 describe-security-groups --region "${AWS_REGION}" --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[?GroupName != 'default'].GroupId" --output text | xargs -r -n1 aws ec2 delete-security-group --region "${AWS_REGION}" --group-id || true
  
  # Delete VPC
  aws ec2 delete-vpc --region "${AWS_REGION}" --vpc-id "${VPC_ID}" || echo "⚠️  Could not delete VPC (may have dependencies)"
  
  echo "✅ VPC cleanup attempted"
else
  echo "ℹ️  No VPC found for cluster"
fi

# 3. Check for PostgreSQL
echo ""
echo "3️⃣  Checking for PostgreSQL instances..."
POSTGRES_ID=$(aws rds describe-db-instances \
  --region "${AWS_REGION}" \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${CLUSTER_NAME}')].DBInstanceIdentifier | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "${POSTGRES_ID}" && "${POSTGRES_ID}" != "None" ]]; then
  echo "Found PostgreSQL: ${POSTGRES_ID}"
  aws rds delete-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${POSTGRES_ID}" \
    --skip-final-snapshot \
    --delete-automated-backups || echo "⚠️  Could not delete PostgreSQL"
  echo "✅ PostgreSQL deletion initiated"
else
  echo "ℹ️  No PostgreSQL found"
fi

# 4. Check for Redis
echo ""
echo "4️⃣  Checking for Redis clusters..."
REDIS_ID=$(aws elasticache describe-replication-groups \
  --region "${AWS_REGION}" \
  --query "ReplicationGroups[?contains(ReplicationGroupId, '${CLUSTER_NAME}')].ReplicationGroupId | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "${REDIS_ID}" && "${REDIS_ID}" != "None" ]]; then
  echo "Found Redis: ${REDIS_ID}"
  aws elasticache delete-replication-group \
    --region "${AWS_REGION}" \
    --replication-group-id "${REDIS_ID}" || echo "⚠️  Could not delete Redis"
  echo "✅ Redis deletion initiated"
else
  echo "ℹ️  No Redis found"
fi

# 5. Check for S3 buckets (Quay)
echo ""
echo "5️⃣  Checking for S3 buckets..."
S3_BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'quay') && contains(Name, '${CLUSTER_NAME}')].Name | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "${S3_BUCKET}" && "${S3_BUCKET}" != "None" ]]; then
  echo "Found S3 bucket: ${S3_BUCKET}"
  echo "⚠️  Emptying and deleting bucket..."
  # Remove all objects
  aws s3 rm "s3://${S3_BUCKET}" --recursive || true
  # Remove all versions and delete markers (for versioned buckets)
  aws s3api list-object-versions --bucket "${S3_BUCKET}" --query 'Versions[*].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
    jq -r '.[] | "--key \"\(.Key)\" --version-id \(.VersionId)"' 2>/dev/null | \
    xargs -L1 -I {} sh -c "aws s3api delete-object --bucket ${S3_BUCKET} {}" 2>/dev/null || true
  aws s3api list-object-versions --bucket "${S3_BUCKET}" --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
    jq -r '.[] | "--key \"\(.Key)\" --version-id \(.VersionId)"' 2>/dev/null | \
    xargs -L1 -I {} sh -c "aws s3api delete-object --bucket ${S3_BUCKET} {}" 2>/dev/null || true
  # Force delete bucket
  aws s3 rb "s3://${S3_BUCKET}" --force || echo "⚠️  Could not delete S3 bucket"
  echo "✅ S3 bucket cleanup attempted"
else
  echo "ℹ️  No S3 buckets found"
fi

# 6. Clean up IAM resources
echo ""
echo "6️⃣  Cleaning up IAM resources..."

# IAM User for Quay S3
IAM_USER="${CLUSTER_NAME}-quay-s3-user"
if aws iam get-user --user-name "${IAM_USER}" &>/dev/null; then
  echo "Found IAM user: ${IAM_USER}"
  
  # Delete access keys
  aws iam list-access-keys --user-name "${IAM_USER}" --query 'AccessKeyMetadata[*].AccessKeyId' --output text | \
    xargs -n1 -I {} aws iam delete-access-key --user-name "${IAM_USER}" --access-key-id {} 2>/dev/null || true
  
  # Delete inline policies
  aws iam list-user-policies --user-name "${IAM_USER}" --query 'PolicyNames' --output text | \
    xargs -n1 -I {} aws iam delete-user-policy --user-name "${IAM_USER}" --policy-name {} 2>/dev/null || true
  
  # Delete user
  aws iam delete-user --user-name "${IAM_USER}" 2>/dev/null || true
  echo "✅ IAM user deleted"
else
  echo "ℹ️  No IAM user found: ${IAM_USER}"
fi

# IAM Roles for ROSA HCP (Account Roles)
for role_suffix in "HCP-ROSA-Installer-Role" "HCP-ROSA-Support-Role" "HCP-ROSA-Worker-Role"; do
  ROLE_NAME="${CLUSTER_NAME}-${role_suffix}"
  
  if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    echo "Found IAM role: ${ROLE_NAME}"
    
    # List and detach all attached policies
    aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query 'AttachedPolicies[*].PolicyArn' --output text | \
      xargs -n1 -I {} aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn {} 2>/dev/null || true
    
    # Delete inline policies
    aws iam list-role-policies --role-name "${ROLE_NAME}" --query 'PolicyNames' --output text | \
      xargs -n1 -I {} aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name {} 2>/dev/null || true
    
    # Delete the role
    aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
    echo "✅ IAM role deleted: ${ROLE_NAME}"
  fi
done

# IAM Operator Roles (created by Terraform ROSA module)
echo ""
echo "Cleaning up IAM operator roles..."
for role_suffix in \
  "openshift-image-registry-installer-cloud-credential" \
  "openshift-ingress-operator-cloud-credentials" \
  "kube-system-kms-provider" \
  "openshift-cluster-csi-drivers-ebs-cloud-credentials" \
  "kube-system-capa-controller-manager" \
  "openshift-cloud-network-config-controller-cloud-cre" \
  "kube-system-control-plane-operator" \
  "kube-system-kube-controller-manager"; do
  
  ROLE_NAME="${CLUSTER_NAME}-${role_suffix}"
  
  if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    echo "Found IAM operator role: ${ROLE_NAME}"
    
    # List and detach all attached policies
    aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query 'AttachedPolicies[*].PolicyArn' --output text | \
      xargs -n1 -I {} aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn {} 2>/dev/null || true
    
    # Delete inline policies
    aws iam list-role-policies --role-name "${ROLE_NAME}" --query 'PolicyNames' --output text | \
      xargs -n1 -I {} aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name {} 2>/dev/null || true
    
    # Delete the role
    aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
    echo "✅ IAM operator role deleted: ${ROLE_NAME}"
  fi
done

echo ""
echo "=================================="
echo "✅ Cleanup completed!"
echo ""
echo "Note: Some resources may take time to delete (VPC dependencies, etc.)"
echo "You can now run the pipeline for a clean deployment."
