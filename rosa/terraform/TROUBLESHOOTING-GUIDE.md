# 🚨 Terraform Troubleshooting Guide

When the terraform apply/destroy/apply cycle doesn't work correctly, follow this systematic approach.

## **🔧 Quick Diagnosis**

Run the troubleshooting tool first:

```bash
# Diagnose the current state
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 diagnose
```

This will show you:
- What's in Terraform state vs. what exists in AWS
- Resource status (creating, deleting, available, etc.)
- Specific recovery suggestions for your situation

## **📋 Common Failure Scenarios & Solutions**

### **Scenario 1: `terraform apply` fails with "already exists"**

**Error examples:**
```
Error: creating S3 Bucket: BucketAlreadyOwnedByYou
Error: creating IAM Role: EntityAlreadyExists
Error: creating ElastiCache Subnet Group: CacheSubnetGroupAlreadyExists
```

**Solution:**
```bash
# 1. Check what conflicts exist
./preflight-check.sh sap-eic-rosa eu-north-1

# 2. Clean up conflicting resources
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false

# 3. Verify cleanup
./preflight-check.sh sap-eic-rosa eu-north-1

# 4. Re-apply
terraform apply
```

### **Scenario 2: `terraform destroy` partially fails**

**Error examples:**
```
Error: deleting ElastiCache Subnet Group: DependencyViolation
Error: deleting Security Group: DependencyViolation
Error: deleting S3 Bucket: BucketNotEmpty
```

**Solution:**
```bash
# 1. Check what's left
terraform state list
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 diagnose

# 2. Try targeted destroy
terraform destroy -target=aws_elasticache_replication_group.redis
terraform destroy -target=aws_db_instance.postgres

# 3. If still failing, manual cleanup
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false

# 4. Clean up Terraform state
terraform refresh
```

### **Scenario 3: State drift (Terraform thinks resources exist but they don't)**

**Symptoms:**
```
terraform plan shows resources to create, but AWS says they exist
terraform destroy says "no resources to destroy" but AWS has resources
```

**Solution:**
```bash
# 1. Reset everything
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 reset

# 2. If that doesn't work, nuclear option:
terraform state rm $(terraform state list)
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false
```

### **Scenario 4: ROSA cluster deletion issues**

**Error examples:**
```
Error: deleting ROSA cluster: cluster is still deleting
Error: IAM roles still in use by ROSA
```

**Solution:**
```bash
# 1. Check ROSA cluster status
rosa list clusters
rosa describe cluster sap-eic-rosa

# 2. If cluster is stuck deleting:
rosa delete cluster sap-eic-rosa --yes

# 3. Wait for complete deletion (can take 10-30 minutes)
watch "rosa list clusters | grep sap-eic-rosa || echo 'Cluster deleted'"

# 4. Clean up remaining resources
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false
```

### **Scenario 5: Security Group deletion fails**

**Error examples:**
```
Error: deleting Security Group: DependencyViolation
Error: Security group is associated with network interface
```

**Solution:**
```bash
# 1. Check dependencies
aws ec2 describe-security-groups --group-names sap-eic-rosa-postgres-sg

# 2. Delete by ID (more reliable)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=sap-eic-rosa-postgres-sg --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 delete-security-group --group-id $SG_ID

# 3. If still attached, wait for resources to fully delete
sleep 60
aws ec2 delete-security-group --group-id $SG_ID
```

## **🛠 Step-by-Step Recovery Process**

### **When Everything is Broken:**

```bash
# Step 1: Diagnose
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 diagnose

# Step 2: Try gentle reset
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 reset

# Step 3: If still broken, nuclear option
echo "⚠️  NUCLEAR RESET - This will destroy everything"
read -p "Continue? (yes/no): " confirm
if [[ $confirm == "yes" ]]; then
    # Delete ROSA cluster manually
    rosa delete cluster sap-eic-rosa --yes || echo "ROSA delete failed"

    # Wait for ROSA deletion
    echo "Waiting for ROSA cluster deletion..."
    while rosa list clusters 2>/dev/null | grep -q sap-eic-rosa; do
        echo "  Still deleting..."
        sleep 30
    done

    # Clear Terraform state
    terraform state rm $(terraform state list) 2>/dev/null || echo "State already empty"

    # Clean up all AWS resources
    ./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false

    # Verify clean slate
    ./preflight-check.sh sap-eic-rosa eu-north-1

    echo "✅ Nuclear reset complete - ready for fresh deployment"
fi

# Step 4: Fresh start
terraform plan
terraform apply
```

## **🔍 Advanced Debugging**

### **Check Resource Dependencies:**
```bash
# See what's preventing resource deletion
aws ec2 describe-network-interfaces --filters Name=group-id,Values=sg-xxxxx
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,VpcSecurityGroups[*].VpcSecurityGroupId]'
```

### **Manual Resource Inspection:**
```bash
# List all resources with your cluster name
aws resourcegroupstaggingapi get-resources --tag-filters Key=Cluster,Values=sap-eic-rosa

# Check specific resource states
aws rds describe-db-instances --db-instance-identifier sap-eic-rosa-postgres
aws elasticache describe-replication-groups --replication-group-id sap-eic-rosa-redis
```

### **Force Delete Stuck Resources:**
```bash
# RDS with protection
aws rds modify-db-instance --db-instance-identifier sap-eic-rosa-postgres --no-deletion-protection
aws rds delete-db-instance --db-instance-identifier sap-eic-rosa-postgres --skip-final-snapshot

# S3 with versioning
aws s3api put-bucket-versioning --bucket sap-eic-rosa-quay-registry --versioning-configuration Status=Suspended
aws s3 rm s3://sap-eic-rosa-quay-registry --recursive
```

## **🚨 Prevention Tips**

### **Before Every Deployment:**
```bash
# Always run preflight check
./preflight-check.sh sap-eic-rosa eu-north-1

# Check Terraform state consistency
terraform plan | head -20
```

### **Before Destroy:**
```bash
# Check for external dependencies
./troubleshoot-terraform.sh sap-eic-rosa eu-north-1 diagnose

# Use targeted destroys for problematic resources
terraform destroy -target=aws_elasticache_replication_group.redis
```

### **Safe Practices:**
```bash
# Always use different cluster names for testing
export TF_VAR_cluster_name="sap-eic-rosa-test-$(date +%m%d)"

# Keep backups of working state
terraform state pull > terraform.tfstate.backup
```

## **📞 When All Else Fails**

If you're completely stuck:

1. **Change the cluster name** in your pipeline parameters
2. **Use a different AWS region** temporarily
3. **Create fresh AWS account/profile** for testing
4. **Contact Red Hat support** for ROSA-specific issues

Remember: These scripts and procedures will handle 95% of issues. The nuclear reset option will handle the remaining 5%.