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

### `generate-kubeconfig-local.sh`

Generate a long-lived kubeconfig file locally using a Service Account with permanent token.

**Usage:**

```bash
# Step 1: Login to your ROSA cluster first
rosa login --token=<your-red-hat-ocm-token>
oc login https://api.sap-eic-rosa.xxx.openshiftapps.com --username cluster-admin --password <admin-password>

# Step 2: Generate the kubeconfig
./hack/rosa/generate-kubeconfig-local.sh
```

**What it does:**
- Creates a Service Account (`cluster-admin-sa`) in `default` namespace
- Grants `cluster-admin` role to the Service Account
- Creates a permanent token Secret (type: `kubernetes.io/service-account-token`)
- Extracts the token from the Secret
- Builds a kubeconfig file with the permanent token
- Saves kubeconfig to `./kubeconfig`

**Why use this instead of `oc login`?**
- ✅ **Permanent token** - Never expires (unlike `oc login` sessions)
- ✅ **No interactive login** - Perfect for automation/scripts
- ✅ **Stable kubeconfig** - Same token every time (idempotent)
- ✅ **CI/CD friendly** - Can be used in pipelines and automation
- ✅ **No OAuth dance** - Direct token-based authentication

**Output:**

```bash
🔑 Generating long-lived kubeconfig for ROSA cluster...
============================================

✅ Already logged in as: cluster-admin

1. Creating Service Account 'cluster-admin-sa' in namespace 'default'...
   ✅ Service Account created

2. Granting 'cluster-admin' role to the Service Account...
   ✅ Cluster-admin role granted

3. Creating permanent token Secret for Service Account...
   ✅ Secret created

4. Waiting for Kubernetes to populate the token in the Secret...
   ✅ Token populated by Kubernetes (length: 1234 characters)

5. Fetching cluster server URL...
   API Server: https://api.sap-eic-rosa.xxx.openshiftapps.com:6443

6. Building the kubeconfig file...
   ✅ Kubeconfig file created: kubeconfig

📄 Kubeconfig Summary:
========================
File: kubeconfig
Cluster: api.sap-eic-rosa.xxx.openshiftapps.com:6443
User: cluster-admin-sa
Namespace: default
Token Length: 1234 characters
========================

🔍 Verifying kubeconfig...
system:serviceaccount:default:cluster-admin-sa
✅ Kubeconfig is valid and working!

You can now use this kubeconfig:
  export KUBECONFIG=$(pwd)/kubeconfig
  oc get nodes

✅ Done!
```

**Using the generated kubeconfig:**

```bash
# Use the kubeconfig
export KUBECONFIG=./kubeconfig
oc whoami
# Output: system:serviceaccount:default:cluster-admin-sa

# Verify access
oc get nodes
oc get pods -A

# The token is permanent - kubeconfig works forever! ✅
```

**Idempotent behavior:**
- Running the script multiple times is safe
- If Service Account already exists → reuses it
- If Secret already exists → extracts same token
- Same kubeconfig every time! ✅

**Cleanup (if needed):**

```bash
# Delete the Service Account and Secret
oc delete sa cluster-admin-sa -n default
oc delete secret cluster-admin-sa-token -n default

# Regenerate with fresh token
./hack/rosa/generate-kubeconfig-local.sh
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

