# Terraform Dependency Fixes

This document describes the fixes implemented to resolve Terraform dependency issues and prevent resource conflicts during ROSA cluster deployments.

## 🚨 Problem Summary

The original Terraform configuration had several dependency and lifecycle management issues:

1. **Missing explicit dependencies** between ROSA cluster and AWS services
2. **S3 bucket versioning** preventing clean deletion
3. **ElastiCache and RDS subnet groups** with implicit VPC dependencies
4. **State drift** when `terraform destroy` failed partially
5. **ROSA IAM roles** conflicting on recreate (managed by ROSA, not Terraform)

## ✅ Fixes Implemented

### 1. **Enhanced aws-services.tf Dependencies**

Added explicit `depends_on` relationships:

```hcl
# Subnet groups depend on VPC
resource "aws_db_subnet_group" "postgres" {
  depends_on = [module.vpc]
  # ...
}

# AWS services depend on ROSA cluster
resource "aws_db_instance" "postgres" {
  depends_on = [module.rosa-hcp]
  # ...
}

# S3 bucket with force destroy enabled
resource "aws_s3_bucket" "quay" {
  force_destroy = true  # Allow deletion even with objects inside
  depends_on = [module.rosa-hcp]
  # ...
}
```

### 2. **Resource Cleanup Scripts**

#### **Preflight Check** (`preflight-check.sh`)
Detects resource conflicts before deployment:

```bash
# Check for conflicts
./preflight-check.sh sap-eic-rosa eu-north-1

# Success output:
✅ No resource conflicts detected. Terraform deployment should proceed successfully.
```

#### **Cleanup Script** (`cleanup-orphaned-resources.sh`)
Removes orphaned resources when Terraform state is out of sync:

```bash
# Dry run (safe preview)
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 true

# Actual cleanup
./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false
```

## 🔄 Proper Destruction Order

With these fixes, Terraform will now destroy resources in the correct order:

1. **AWS services destroyed first**: S3, RDS, ElastiCache, Security Groups
2. **ROSA cluster destroyed**: Releases IAM roles for potential deletion
3. **VPC destroyed last**: After all dependent resources are gone

## 🛠 Usage Guide

### For New Deployments

1. **Run preflight check**:
   ```bash
   ./preflight-check.sh sap-eic-rosa eu-north-1
   ```

2. **If conflicts detected**, either:
   - Change cluster name in pipeline
   - Run cleanup script: `./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false`

3. **Deploy normally** with Terraform

### For Failed Deployments

If Terraform apply/destroy fails and leaves orphaned resources:

1. **Check current state**:
   ```bash
   terraform state list
   ./preflight-check.sh sap-eic-rosa eu-north-1
   ```

2. **Clean up orphaned resources**:
   ```bash
   ./cleanup-orphaned-resources.sh sap-eic-rosa eu-north-1 false
   ```

3. **Re-run Terraform**:
   ```bash
   terraform plan
   terraform apply
   ```

## 📋 Resources Managed

### ✅ Terraform Managed (Cleaned by Scripts)
- ElastiCache subnet groups and replication groups
- S3 buckets (with all versions and delete markers)
- RDS instances and subnet groups
- Security groups
- IAM users (Quay S3 access)

### ℹ️ ROSA Managed (Left Alone)
- `sap-eic-rosa-HCP-ROSA-Worker-Role`
- `sap-eic-rosa-HCP-ROSA-Installer-Role`
- `sap-eic-rosa-HCP-ROSA-Support-Role`

These IAM roles are managed by the ROSA service and should not be manually deleted.

## 🚀 Integration with Tekton Pipeline

To integrate these fixes with your pipeline, add these steps:

### Before Terraform Apply
```yaml
- name: preflight-check
  script: |
    cd terraform
    ./preflight-check.sh $(params.clusterName) $(params.awsRegion)
```

### In Finally Block (Cleanup)
```yaml
finally:
  - name: cleanup-orphaned-resources
    when:
      - input: "$(tasks.terraform-destroy.status)"
        operator: in
        values: ["Failed"]
    script: |
      cd terraform
      ./cleanup-orphaned-resources.sh $(params.clusterName) $(params.awsRegion) false
```

## 🔧 Troubleshooting

### Common Issues

1. **Security Group Deletion Fails**:
   ```bash
   # Check dependencies
   aws ec2 describe-security-groups --group-ids sg-xxxxx
   # Delete by ID instead of name
   aws ec2 delete-security-group --group-id sg-xxxxx
   ```

2. **S3 Bucket Not Empty**:
   The `force_destroy = true` should handle this, but if manual cleanup is needed:
   ```bash
   # Delete all versions
   aws s3api delete-objects --bucket BUCKET_NAME --delete "$(aws s3api list-object-versions --bucket BUCKET_NAME --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
   ```

3. **RDS Deletion Protection**:
   ```bash
   aws rds modify-db-instance --db-instance-identifier DB_NAME --no-deletion-protection
   aws rds delete-db-instance --db-instance-identifier DB_NAME --skip-final-snapshot
   ```

## 📅 Maintenance

These scripts should be reviewed when:
- Adding new AWS resources to the Terraform configuration
- Upgrading the ROSA module version
- Changing the cluster naming convention

---

**Note**: Always test changes in a development environment before applying to production pipelines.