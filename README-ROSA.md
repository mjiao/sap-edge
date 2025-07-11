# Red Hat OpenShift on AWS (ROSA) Implementation

This document describes the ROSA implementation that mirrors the existing ARO (Azure Red Hat OpenShift) setup using Infrastructure as Code (IaC) and CI/CD automation.

## Overview

The ROSA implementation provides:
- **Terraform** for AWS infrastructure management (equivalent to Bicep for Azure)
- **Makefile** for deployment orchestration
- **Tekton tasks and pipelines** for CI/CD automation
- **AWS services integration** (RDS PostgreSQL, ElastiCache Redis)

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Terraform     │    │   ROSA CLI      │    │   Tekton        │
│   (AWS Infra)   │    │   (Cluster Mgmt)│    │   (CI/CD)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AWS Services  │    │   ROSA Cluster  │    │   Automation    │
│   • RDS PG      │    │   • OCP 4.15    │    │   • Deploy      │
│   • ElastiCache │    │   • 3 Workers   │    │   • Test        │
│   • VPC/Subnets │    │   • Private Link│    │   • Validate    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Prerequisites

### Required Tools
- **ROSA CLI**: Red Hat OpenShift Service on AWS CLI
- **AWS CLI**: AWS Command Line Interface
- **Terraform**: Infrastructure as Code tool
- **OC CLI**: OpenShift Command Line Interface
- **Make**: Build automation tool

### Required Credentials
- **AWS Access Key ID** and **Secret Access Key**
- **ROSA Token**: Red Hat account token for ROSA access
- **PostgreSQL Admin Password**: For RDS database

## Quick Start

### 1. Set Environment Variables

```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
export ROSA_TOKEN="your-rosa-token"
export ROSA_CLUSTER_NAME="sapeic"
export POSTGRES_ADMIN_PASSWORD="your-secure-password"
```

### 2. Deploy Complete Environment

```bash
# Deploy everything (infrastructure + cluster)
make -f terraform.makefile rosa-deploy
```

### 3. Get Cluster Access

```bash
# Get kubeconfig
make -f terraform.makefile rosa-cluster-oc-login

# Or login directly
oc login "$(rosa describe cluster --cluster sapeic --output json | jq -r '.api.url')" \
  -u "cluster-admin" -p "your-admin-password"
```

## Detailed Usage

### Infrastructure Management

#### Deploy AWS Infrastructure Only
```bash
make -f terraform.makefile terraform-apply
```

#### Plan Infrastructure Changes
```bash
make -f terraform.makefile terraform-plan
```

#### Get Infrastructure Information
```bash
make -f terraform.makefile aws-services-info
```

### Cluster Management

#### Create ROSA Cluster
```bash
make -f terraform.makefile rosa-cluster-create
```

#### Check Cluster Status
```bash
make -f terraform.makefile rosa-cluster-status
```

#### Wait for Cluster Ready
```bash
make -f terraform.makefile rosa-cluster-wait
```

#### Create Cluster Admin
```bash
export CLUSTER_ADMIN_PASSWORD="your-admin-password"
make -f terraform.makefile rosa-cluster-admin
```

### Cleanup

#### Delete Cluster Only
```bash
make -f terraform.makefile rosa-cluster-delete
```

#### Destroy Infrastructure Only
```bash
make -f terraform.makefile terraform-destroy
```

#### Complete Cleanup
```bash
make -f terraform.makefile rosa-cleanup
```

## Tekton Automation

### Available Tasks

1. **rosa-deploy**: Deploy ROSA cluster and AWS infrastructure
2. **rosa-teardown**: Clean up ROSA cluster and infrastructure
3. **rosa-kubeconfig**: Get cluster kubeconfig
4. **aws-services-info**: Display AWS services information
5. **rosa-validate**: Validate cluster health and components

### Pipeline

The `rosa-endpoint-test-pipeline` orchestrates:
1. ROSA deployment
2. Manual approval gate
3. Kubeconfig retrieval
4. AWS services information
5. Endpoint testing
6. Rate limit testing
7. Cluster validation
8. Optional teardown

### Running the Pipeline

```bash
# Create required secrets first
kubectl create secret generic aws-credentials-secret \
  --from-literal=awsAccessKeyId="$AWS_ACCESS_KEY_ID" \
  --from-literal=awsSecretAccessKey="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=awsDefaultRegion="$AWS_DEFAULT_REGION"

kubectl create secret generic rosa-token-secret \
  --from-literal=rosaToken="$ROSA_TOKEN"

kubectl create secret generic aws-postgres-admin-password \
  --from-literal=POSTGRES_ADMIN_PASSWORD="$POSTGRES_ADMIN_PASSWORD"

# Run the pipeline
tkn pipeline start rosa-endpoint-test-pipeline \
  --param rosaClusterName="sapeic" \
  --param rosaRegion="us-east-1" \
  --param autoTeardown="false" \
  --workspace name=source,claimName=rosa-source-pvc
```

## Configuration

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `cluster_name`: ROSA cluster name (default: "sapeic")
- `region`: AWS region (default: "us-east-1")
- `rosa_version`: OpenShift version (default: "4.15.35")
- `deploy_postgres`: Enable RDS PostgreSQL (default: true)
- `deploy_redis`: Enable ElastiCache Redis (default: true)
- `worker_count`: Number of worker nodes (default: 3)

### Makefile Variables

Key variables in `terraform.makefile`:

- `ROSA_CLUSTER_NAME`: Cluster name (default: "sapeic")
- `ROSA_REGION`: AWS region (default: "us-east-1")
- `ROSA_VERSION`: OpenShift version (default: "4.15.35")
- `DEPLOY_POSTGRES`: Deploy PostgreSQL (default: true)
- `DEPLOY_REDIS`: Deploy Redis (default: true)

## AWS Services

### RDS PostgreSQL
- **Instance Class**: db.t3.micro (configurable)
- **Storage**: 20GB GP2 (configurable)
- **Engine**: PostgreSQL 15.4
- **Database**: sapeic
- **Admin User**: postgres

### ElastiCache Redis
- **Node Type**: cache.t3.micro (configurable)
- **Engine**: Redis 7
- **Port**: 6379
- **Nodes**: 1 (single node)

### Networking
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 3 subnets across AZs
- **Private Subnets**: 3 subnets across AZs
- **Security Groups**: Cluster, PostgreSQL, Redis

## Comparison with ARO

| Component | ARO | ROSA |
|-----------|-----|------|
| **Infrastructure** | Bicep (Azure) | Terraform (AWS) |
| **Database** | Azure Database for PostgreSQL | RDS PostgreSQL |
| **Cache** | Azure Cache for Redis | ElastiCache Redis |
| **Networking** | Azure VNet | AWS VPC |
| **CLI Tool** | Azure CLI | AWS CLI + ROSA CLI |
| **Cluster** | Azure Red Hat OpenShift | Red Hat OpenShift on AWS |

## Troubleshooting

### Common Issues

1. **ROSA CLI not found**
   ```bash
   curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar -xz
   sudo mv rosa /usr/local/bin/
   ```

2. **AWS credentials not working**
   ```bash
   aws configure
   # Or set environment variables
   export AWS_ACCESS_KEY_ID="your-key"
   export AWS_SECRET_ACCESS_KEY="your-secret"
   ```

3. **Terraform state issues**
   ```bash
   cd terraform
   terraform init
   terraform plan
   ```

4. **Cluster stuck in provisioning**
   ```bash
   rosa logs install --cluster sapeic --watch
   ```

### Logs and Debugging

```bash
# ROSA cluster logs
rosa logs install --cluster sapeic --watch

# Terraform logs
cd terraform && terraform plan -detailed-exitcode

# AWS resource status
aws rds describe-db-instances --db-instance-identifier sapeic-postgres
aws elasticache describe-cache-clusters --cache-cluster-id sapeic-redis
```

## Security Considerations

1. **Credentials**: Store AWS and ROSA credentials securely
2. **Passwords**: Use strong passwords for PostgreSQL admin
3. **Network**: Private subnets for databases, security groups for access control
4. **Encryption**: RDS and ElastiCache use encryption at rest
5. **IAM**: Use least privilege principle for AWS IAM roles

## Cost Optimization

1. **Instance Types**: Use t3.micro for development/testing
2. **Storage**: Start with minimal storage, scale as needed
3. **Hibernation**: Use `rosa hibernate cluster` for cost savings
4. **Cleanup**: Always clean up resources when not needed

## Support

For issues related to:
- **ROSA**: Contact Red Hat support
- **AWS**: Contact AWS support
- **Terraform**: Check Terraform documentation
- **This Implementation**: Check the project repository 