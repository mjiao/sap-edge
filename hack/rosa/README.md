<!-- SPDX-FileCopyrightText: 2025 SAP edge team -->
<!-- SPDX-FileContributor: Manjun Jiao (@mjiao) -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# ROSA Utility Scripts

Helper scripts for ROSA (Red Hat OpenShift Service on AWS) cluster management.

## Scripts

### `terraform-init-local.sh`

Initialize Terraform locally to access the same S3 backend state used by the pipeline.

**Usage:**

```bash
./hack/rosa/terraform-init-local.sh
```

**What it does:**
- Prompts for AWS credentials (if not already set)
- Prompts for Red Hat OCM token (if not already set)
- Prompts for cluster name (default: `sap-eic-rosa`)
- Initializes Terraform with S3 backend configuration
- Verifies state file access
- Shows resources in state

**Prerequisites:**
- AWS CLI installed and configured
- Terraform installed (v1.4.6+)
- Valid AWS credentials with access to the S3 bucket and DynamoDB table
- (Optional) Red Hat OCM token for plan/apply operations

**Example:**

```bash
# Set credentials via environment variables (optional)
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export TF_VAR_redhat_ocm_token="eyJhbGc..."

# Run the script
./hack/rosa/terraform-init-local.sh

# After initialization, you can run Terraform commands:
cd rosa/terraform
terraform state list
terraform output
terraform plan
```

---

### `cleanup-rosa-resources.sh`

Manually delete ROSA cluster and all related AWS resources.

**Usage:**

```bash
# Set credentials
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="eu-north-1"

# Run cleanup
./hack/rosa/cleanup-rosa-resources.sh
```

**What it deletes:**
- ROSA cluster (via ROSA CLI)
- VPC and networking resources (NAT gateways, Internet gateways, subnets, route tables, security groups)
- RDS PostgreSQL instances (if exists)
- ElastiCache Redis clusters (if exists)
- S3 buckets for Quay (if exists)

**⚠️ Warning:**
This is a destructive operation! Make sure you want to delete the cluster before running.

**Time:** Cluster deletion takes approximately 30-45 minutes.

---

### `quay-s3-create.sh`

Create S3 bucket and IAM user for Quay registry storage.

**Usage:**

See script documentation for details.

---

## S3 Backend Configuration

All ROSA clusters use a shared S3 backend for Terraform state:

- **Bucket:** `eic-test-rosa-terraform-state`
- **Region:** `eu-north-1`
- **DynamoDB Table:** `eic-test-rosa-terraform-state-lock`
- **Key Pattern:** `rosa/${CLUSTER_NAME}/terraform.tfstate`

Each cluster has its own state file isolated by cluster name.

---

## Tips

### Read-only Operations (Safe)
```bash
terraform show           # View current state
terraform state list     # List all resources
terraform output         # Get outputs
terraform plan           # Preview changes
```

### Write Operations (Use with Caution)
```bash
terraform apply          # Apply changes
terraform destroy        # Destroy resources
```

**⚠️ Before running apply/destroy:**
- Coordinate with your team
- Ensure no pipeline is running
- DynamoDB locking will prevent concurrent modifications, but be careful!

### Handling Stuck Locks

If Terraform crashes or is interrupted, you might need to manually remove the lock:

```bash
# Check for locks
aws dynamodb scan \
  --table-name eic-test-rosa-terraform-state-lock \
  --region eu-north-1

# Delete lock if stuck
aws dynamodb delete-item \
  --table-name eic-test-rosa-terraform-state-lock \
  --key '{"LockID":{"S":"eic-test-rosa-terraform-state/rosa/sap-eic-rosa/terraform.tfstate"}}' \
  --region eu-north-1
```

---

## See Also

- [ROSA Terraform Configuration](../../rosa/terraform/README.md)
- [Tekton Pipelines Documentation](../../.tekton/README.md)

