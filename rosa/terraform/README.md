%% SPDX-FileCopyrightText: 2025 SAP edge team
%% SPDX-FileContributor: Kirill Satarin (@kksat)
%% SPDX-FileContributor: Manjun Jiao (@mjiao)
%% SPDX-FileContributor: Rishabh Bhandari (@RishabhKodes)
%%
%% SPDX-License-Identifier: Apache-2.0

# ROSA Terraform Infrastructure

This directory contains Terraform configuration files for provisioning AWS infrastructure required for Red Hat OpenShift Service on AWS (ROSA) clusters.

## Overview

The infrastructure creates a highly available VPC with public and private subnets across 3 availability zones, designed to support ROSA cluster deployment. The configuration uses both AWS and Red Hat Cloud Services (RHCS) providers.

This Terraform configuration also supports deploying AWS RDS PostgreSQL and ElastiCache Redis directly, providing infrastructure-as-code practices and consistent deployment for ROSA clusters.

## Architecture

### Network Design
- **VPC**: Single VPC with configurable CIDR block
- **Subnets**: 6 subnets total across 3 availability zones:
  - 3 public subnets
  - 3 private subnets
- **NAT Gateways**: One NAT gateway per availability zone for private subnet internet access
- **Internet Gateway**: Single IGW for public subnet internet access
- See default parameters in variables.tf file

### AWS Services (Optional)
- **RDS PostgreSQL**: Fully managed PostgreSQL database deployed in private subnets
- **ElastiCache Redis**: Fully managed Redis cache deployed in private subnets
- **S3 Bucket for Quay**: Object storage for Quay container registry (enabled by default)
- Database services are configured with security groups limiting access to VPC CIDR only
- S3 bucket includes versioning, encryption, and dedicated IAM user with minimal permissions

## Files

| File | Purpose |
|------|---------|
| `provider.tf` | Provider configurations for AWS and RHCS, including backend configuration |
| `variables.tf` | Variable definitions with descriptions and default values |
| `network.tf` | VPC, subnets, route tables, NAT gateways, and networking resources |
| `rosa.tf` | ROSA cluster configuration |
| `aws-services.tf` | AWS RDS PostgreSQL and ElastiCache Redis configuration |
| `outputs.tf` | Output definitions for all resources |
| `backend.config` | S3 backend configuration for state management |

## Prerequisites

1. **Terraform**: Version >= 1.4.6
2. **AWS CLI**: Configured with appropriate credentials
3. **ROSA CLI**: Install the ROSA CLI
   ```bash
   rosa download rosa
   rosa verify permissions
   ```
4. **Red Hat Account**: Valid Red Hat account with ROSA access
5. **RHCS Token**: Red Hat Cloud Services token for OpenShift API access
   ```bash
   rosa login
   # Or set environment variable:
   export RHCS_TOKEN="your-token-here"
   ```
6. **S3 Backend** (Optional): Existing S3 bucket and DynamoDB table for state management

## One-Time Setup: IAM Roles

Before deploying ROSA clusters, you need to create account-wide IAM roles **once**. This is recommended to avoid IAM role lifecycle issues during `terraform destroy`.

```bash
# Login to Red Hat OCM
rosa login --token=<your-ocm-token>

# Create account roles (one-time, reusable across clusters)
rosa create account-roles --prefix ManagedOpenShift --mode auto --yes

# Create OIDC config (one-time)
rosa create oidc-config --mode auto --yes
```

**Why pre-create roles?**
- ROSA attaches additional policies to IAM roles after cluster creation
- Terraform can't track these changes, causing destroy failures
- Pre-created roles with `ManagedOpenShift` prefix are managed by ROSA service
- This avoids `EntityAlreadyExists` errors on re-deployment

To verify roles exist:
```bash
rosa list account-roles
rosa list oidc-config
```

## Configuration

### Required Variables

Set these variables in `.env` file or as environment variables:

```.env
CLUSTER_NAME="your-cluster-name"
AWS_REGION="your-aws-region"
VPC_NAME="your-vpc-name"
TF_VAR_admin_username="kubeadmin"
TF_VAR_admin_password=""
TERRAFORM_BACKEND_S3_BUCKET=
TERRAFORM_BACKEND_S3_KEY=
TERRAFORM_BACKEND_S3_AWS_REGION=
TERRAFORM_BACKEND_S3_DYNAMODB_TABLE=
```

### Optional Variables

All subnet CIDR blocks and environment tag can be customized. See `variables.tf` for defaults.

### AWS Services Configuration

To deploy AWS RDS PostgreSQL and ElastiCache Redis alongside your ROSA cluster:

```bash
# Set PostgreSQL admin password
export TF_VAR_postgres_admin_password="your-secure-password"

# Optional: Customize PostgreSQL configuration
export TF_VAR_postgres_version="15.5"
export TF_VAR_postgres_instance_class="db.t3.micro"
export TF_VAR_postgres_allocated_storage=20

# Optional: Customize Redis configuration
export TF_VAR_redis_engine_version="7.0"
export TF_VAR_redis_node_type="cache.t3.micro"

# Deploy services (enabled by default)
# To disable: export TF_VAR_deploy_postgres=false
# To disable: export TF_VAR_deploy_redis=false
```

#### AWS Services Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `deploy_postgres` | Deploy AWS RDS PostgreSQL | `false` | ❌ |
| `deploy_redis` | Deploy AWS ElastiCache Redis | `false` | ❌ |
| `deploy_quay` | Deploy S3 bucket for Quay registry | `true` | ❌ |
| `postgres_version` | PostgreSQL engine version | `15.5` | ❌ |
| `postgres_instance_class` | RDS instance class | `db.t3.micro` | ❌ |
| `postgres_allocated_storage` | Storage size in GB | `20` | ❌ |
| `postgres_admin_username` | PostgreSQL admin username | `eicadmin` | ❌ |
| `postgres_admin_password` | PostgreSQL admin password | - | ✅ (if PostgreSQL enabled) |
| `postgres_publicly_accessible` | Make PostgreSQL publicly accessible | `false` | ❌ |
| `postgres_allowed_cidr_blocks` | CIDR blocks allowed to access PostgreSQL | `["10.0.0.0/16"]` (VPC CIDR) | ❌ |
| `redis_engine_version` | Redis engine version | `7.0` | ❌ |
| `redis_node_type` | ElastiCache node type | `cache.t3.micro` | ❌ |
| `redis_allowed_cidr_blocks` | CIDR blocks allowed to access Redis | `["10.0.0.0/16"]` (VPC CIDR) | ❌ |

> **🔒 Security Note**  
> **Database Services**: PostgreSQL and Redis are deployed in private subnets and only accessible from within the VPC (10.0.0.0/16). For production, further restrict CIDR blocks to specific subnet ranges.
>
> **Quay Storage**: S3 bucket is created with:
> - Versioning enabled for data protection
> - Server-side encryption (AES256)
> - Public access blocked
> - Dedicated IAM user with minimal S3 permissions
> - Access keys available as Terraform outputs (sensitive)

## Usage

### Quick Start

1. **Set required environment variables**:
   ```bash
   export CLUSTER_NAME="my-rosa-test"  # Max 15 characters!
   export AWS_REGION="us-east-1"
   export VPC_NAME="${CLUSTER_NAME}-vpc"
   export RHCS_TOKEN="your-rhcs-token"
   
   # For AWS services (optional)
   export TF_VAR_postgres_admin_password="your-secure-password"
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Create terraform.tfvars**:
   ```hcl
   cluster_name  = "my-rosa-test"  # Max 15 characters!
   aws_region    = "us-east-1"
   vpc_name      = "my-rosa-vpc"
   rosa_version  = "4.14.9"
   
   # Worker node instance type (default: m5.2xlarge - 8 vCPU, 32 GB RAM)
   compute_machine_type = "m5.2xlarge"
   
   # Optional: AWS Services
   deploy_postgres = true
   deploy_redis    = true
   postgres_admin_password = "your-secure-password"
   ```

4. **Plan and apply**:
   ```bash
   terraform plan
   terraform apply
   ```

5. **Access your cluster**:
   ```bash
   # Get cluster details
   terraform output rosa_cluster_api_url
   terraform output rosa_cluster_console_url
   
   # Login to cluster
   rosa describe cluster -c $(terraform output -raw rosa_cluster_id)
   rosa create admin -c $(terraform output -raw rosa_cluster_id)
   ```

6. **Deploy Quay Container Registry** (Optional):

   Quay S3 storage is automatically created by Terraform. To deploy Quay on your ROSA cluster:
   
   ```bash
   # From rosa/terraform directory
   
   # Step 1: Get S3 credentials from Terraform outputs
   export S3_BUCKET_NAME=$(terraform output -raw quay_s3_bucket_name)
   export S3_REGION=$(terraform output -raw quay_s3_bucket_region)
   export S3_HOST="s3.${S3_REGION}.amazonaws.com"
   export AWS_ACCESS_KEY_ID=$(terraform output -raw quay_s3_access_key_id)
   export AWS_SECRET_ACCESS_KEY=$(terraform output -raw quay_s3_secret_access_key)
   
   # Step 2: Set Quay admin credentials
   export QUAY_ADMIN_PASSWORD="YourSecurePassword"
   export QUAY_ADMIN_EMAIL="admin@example.com"
   export CLUSTER_NAME=$(terraform output -raw rosa_cluster_name)
   
   # Step 3: Deploy Quay using Ansible (from project root)
   cd ../..
   make rosa-quay-deploy
   ```
   
   The Ansible playbook will:
   - Deploy the Quay operator
   - Configure S3 storage backend
   - Deploy the Quay registry instance
   - Create admin user
   - Configure certificate trust

7. **Destroy infrastructure**:
   ```bash
   terraform destroy
   ```
   
   > **💡 Note**: This will destroy all resources including the ROSA cluster, VPC, and S3 bucket with all registry data.

## License

Apache-2.0
