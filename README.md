<!--
SPDX-FileCopyrightText: 2024 SAP edge team
SPDX-FileContributor: Kirill Satarin (@kksat)
SPDX-FileContributor: Manjun Jiao (@mjiao)

SPDX-License-Identifier: Apache-2.0
-->

# SAP Edge Integration Cell (EIC) - External Services & ARO Pipeline

This repository provides comprehensive tooling for deploying and testing SAP Edge Integration Cell (EIC) external services and Azure Red Hat OpenShift (ARO) clusters. It includes automated CI/CD pipelines, GitOps configurations, and manual deployment procedures.

## 📋 Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [External Services Setup](#external-services-setup)
  - [PostgreSQL](#postgresql)
  - [Redis](#redis)
  - [GitOps with Argo CD](#gitops-with-argo-cd)
- [ARO Pipeline](#aro-pipeline)
  - [Pipeline Structure](#pipeline-structure)
  - [Prerequisites](#prerequisites-for-aro-pipeline)
  - [Running the Pipeline](#running-the-aro-pipeline)
  - [Parameters Reference](#pipeline-parameters)
  - [Monitoring & Cleanup](#monitoring--cleanup)
- [Endpoint Testing](#endpoint-testing)
- [Support & Operations](#support--operations)
- [License](#license)

## 🎯 Overview

This repository provides scripts and procedures for setting up test validation external services for SAP EIC on the OpenShift Container Platform (OCP). The services covered include:

- **PostgreSQL** (via Crunchy Data Operator)
- **Redis** (via Redis Enterprise Operator)  
- **Azure Red Hat OpenShift (ARO)** deployment and testing pipeline
- **Automated CI/CD pipelines** using Tekton
- **GitOps workflows** using Argo CD

> **Note:** These services may be optional for a proof of concept (PoC) setup.
> If you don't enable or configure the external Postgres and Redis during the SAP Edge Integration Cell (EIC) installation, EIC will automatically deploy self-contained Postgres and Redis pods within its own service namespace.

## ⚠️ Important Notice

Please be aware that this repository is intended **for testing purposes only**. The configurations and scripts provided are designed to assist in test validation scenarios and are not recommended for production use.

## 🚀 Quick Start

### For External Services Only
```bash
# Clone the repository
git clone https://github.com/redhat-sap/sap-edge.git
cd sap-edge

# Deploy via GitOps (recommended)
oc apply -f edge-integration-cell/sap-eic-external-services-app.yaml

# Or deploy manually - see detailed sections below
```

### For ARO Pipeline
```bash
# 1. Create required secrets (see ARO Pipeline section)
# 2. Copy and customize pipeline run
cp .tekton/aro-endpoint-test-run.yaml .tekton/my-aro-test.yaml
# 3. Edit parameters and apply
oc apply -f .tekton/my-aro-test.yaml
```

## 📋 Prerequisites

- Access to an OpenShift Container Platform cluster using an account with `cluster-admin` permissions
- Installed command line tools: `oc`, `jq`, `git`
- For ARO Pipeline: Azure subscription with appropriate permissions
- For GitOps: OpenShift GitOps Operator installed

## 🔧 Shared Storage

When ODF (OpenShift Data Foundation) is installed, set the shared file system parameters as follows:

| Property                     | Settings                        |
|------------------------------|---------------------------------|
| Enable Shared File System    | yes                             |
| Shared File System Storage Class | ocs-storagecluster-cephfs   |

Additionally, set the ODF `ocs-storagecluster-ceph-rbd` storage class as default for RWO/RWX Block volumes to meet most block storage requirements for various services running on OpenShift.

# External Services Setup

## PostgreSQL

The following steps will install the Crunchy Postgres Operator and use its features to manage the lifecycle of the external PostgreSQL DB service.

1. Clone the repository:
    ```bash
    git clone https://github.com/redhat-sap/sap-edge.git
    ```
2. Create a new project:
    ```bash
    oc new-project sap-eic-external-postgres
    ```
3. Apply the OperatorGroup configuration:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/postgres-operator/operatorgroup.yaml
    ```
4. Apply the Subscription configuration:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/postgres-operator/subscription.yaml
    ```
5. Wait for the Postgres operator to be ready:
    ```bash
    bash sap-edge/edge-integration-cell/external-postgres/wait_for_postgres_operator_ready.sh
    ```
6. Create a PostgresCluster:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/external-postgres/postgrescluster-v15.yaml
    ```
    - For other versions, replace `v15` with `v16` or `v17`.
7. Wait for Crunchy Postgres to be ready:
    ```bash
    bash sap-edge/edge-integration-cell/external-postgres/wait_for_postgres_ready.sh
    ```
8. Get access details of Crunchy Postgres:
    ```bash
    bash sap-edge/edge-integration-cell/external-postgres/get_external_postgres_access.sh
    ```

After running the above script, you will get the access details of Crunchy Postgres like the following:
- External DB Hostname: `hippo-primary.sap-eic-external-postgres.svc`
- External DB Port: `5432`
- External DB Name: `eic`
- External DB Username: `eic`
- External DB Password: `xklaieniej12#`
- External DB TLS Root Certificate saved to `external_postgres_db_tls_root_cert.crt`

Please use the provided information to set up the EIC external DB accordingly.

### Cleanup PostgreSQL

To clean up the PostgresCluster:

```bash
oc delete postgrescluster eic -n sap-eic-external-postgres
bash sap-edge/edge-integration-cell/external-postgres/wait_for_deletion_of_postgrescluster.sh
oc delete subscription crunchy-postgres-operator -n sap-eic-external-postgres
oc get csv -n sap-eic-external-postgres --no-headers | grep 'postgresoperator' | awk '{print $1}' | xargs -I{} oc delete csv {} -n sap-eic-external-postgres
oc delete namespace sap-eic-external-postgres
```

# Redis Setup for SAP EIC on OCP

This guide provides instructions for setting up and validating the Redis service for SAP EIC on OpenShift Container Platform (OCP). The steps include installing the Redis Enterprise Operator, creating a RedisEnterpriseCluster and RedisEnterpriseDatabase, and cleaning up after validation.

## Prerequisites

- Access to an OpenShift Container Platform cluster using an account with `cluster-admin` permissions.
- Installed `oc`, `jq`, and `git` command line tools on your local system.

## Redis Setup

The following steps will install the Redis Enterprise Operator and use its features to manage the lifecycle of the external Redis datastore service.

1. Clone the repository:
    ```bash
    git clone https://github.com/redhat-sap/sap-edge.git
    ```
2. Create a new project:
    ```bash
    oc new-project sap-eic-external-redis
    ```
3. Apply the OperatorGroup configuration:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/operatorgroup.yaml
    ```
4. Apply the Subscription configuration:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/subscription.yaml
    ```
5. Apply the [Security Context Constraint (SCC)](https://redis.io/docs/latest/operate/kubernetes/deployment/openshift/openshift-cli/#install-security-context-constraint):
   - For OpenShift versions 4.16 and later, use
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/security_context_constraint_v2.yaml
    ```
   - For OpenShift versions earlier than 4.16, use:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/security_context_constraint.yaml
    ```
6. Wait for the Redis operator to be ready:
    ```bash
    bash sap-edge/edge-integration-cell/external-redis/wait_for_redis_operator_ready.sh
    ```
7. Create a RedisEnterpriseCluster:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/external-redis/redis_enterprise_cluster.yaml
    ```
8. Wait for the RedisEnterpriseCluster to be ready:
    ```bash
    bash sap-edge/edge-integration-cell/external-redis/wait_for_rec_running_state.sh
    ```
9. Create a RedisEnterpriseDatabase:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/external-redis/redis_enterprise_database.yaml
    ```
    - Note: You might need to run the above command several times until it works because the previously created RedisEnterpriseCluster needs some time to enable the admission webhook successfully.
10. Wait for the RedisEnterpriseDatabase to be ready:
    ```bash
    bash sap-edge/edge-integration-cell/external-redis/wait_for_redb_active_status.sh
    ```
11. Get access details of Redis:
    ```bash
    bash sap-edge/edge-integration-cell/external-redis/get_redis_access.sh
    ```

After running the above script, you will get the access details of Redis like the following:
- External Redis Addresses: `redb-headless.sap-eic-external-redis.svc:12117`
- External Redis Mode: `standalone`
- External Redis Username: `[leave me blank]`
- External Redis Password: `XpglWqoR`
- External Redis Sentinel Username: `[leave me blank]`
- External Redis Sentinel Password: `[leave me blank]`
- External Redis TLS Certificate content saved to `external_redis_tls_certificate.pem`
- External Redis Server Name: `rec.sap-eic-external-redis.svc.cluster.local`

Alternatively, you can run the following script to retrieve access details for both Redis and Postgres:
```bash
bash sap-edge/edge-integration-cell/get_all_access.sh
```

## Cleanup Redis

To clean up the Redis instance:

```bash
oc delete redisenterprisedatabase redb -n sap-eic-external-redis
oc delete redisenterprisecluster rec -n sap-eic-external-redis
bash sap-edge/edge-integration-cell/external-redis/wait_for_deletion_of_rec.sh
oc delete subscription redis-enterprise-operator-cert -n sap-eic-external-redis
oc get csv -n sap-eic-external-redis --no-headers | grep 'redis-enterprise-operator' | awk '{print $1}' | xargs -I{} oc delete csv {} -n sap-eic-external-redis
# For OpenShift versions earlier than 4.16
oc delete scc redis-enterprise-scc-v2
# For OpenShift versions 4.16 and later
oc delete scc redis-enterprise-scc
oc delete namespace sap-eic-external-redis
```

## 🚀 GitOps with Argo CD

This project supports automated deployment of external **Postgres** and **Redis** services using **Argo CD** and a GitOps workflow.

**Requirements**
* OpenShift cluster
* OpenShift GitOps Operator
* Access to this Git repository

### 📁 Folder Structure

Argo CD uses an **App of Apps** model located in:

edge-integration-cell/argocd-apps/


This folder defines four Argo CD Applications:

| Application Name             | Purpose                            | Sync Wave |
|-----------------------------|------------------------------------|-----------|
| `postgres-operator`         | Installs Crunchy Postgres Operator | 0         |
| `external-postgres`         | Deploys PostgresCluster CR         | 1         |
| `external-redis-operator`   | Installs Redis Enterprise Operator | 0         |
| `external-redis`            | Deploys RedisCluster CRs           | 1         |

Each application includes a **sync wave annotation** to ensure the operator is deployed before its related custom resources.

---

### 🔧 Deploying with Argo CD

1. Make sure Argo CD is installed in your cluster (e.g., via 'Red Hat OpenShift GitOps' Operator).
2. Create a **parent Argo CD Application** pointing to the `argocd-apps` folder:

```bash
oc apply -f sap-edge/edge-integration-cell/sap-eic-external-services-app.yaml
```

3. Apply the [Security Context Constraint (SCC)](https://redis.io/docs/latest/operate/kubernetes/deployment/openshift/openshift-cli/#install-security-context-constraint) for the redis deployment:
   - For OpenShift versions 4.16 and later, use
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/security_context_constraint_v2.yaml
    ```
   - For OpenShift versions earlier than 4.16, use:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/redis-operator/security_context_constraint.yaml
    ```
4. The Argo CD Application Controller requires administrative privileges to manage custom resources (CRs) in the `sap-eic-external-postgres` and `sap-eic-external-redis` namespaces. Grant these privileges by applying the provided RBAC role bindings:
    ```bash
    oc apply -f sap-edge/edge-integration-cell/argocd-rbac/argocd-admin-rolebinding-postgres.yaml
    oc apply -f sap-edge/edge-integration-cell/argocd-rbac/argocd-admin-rolebinding-redis.yaml
    ```
5. Argo CD will:
* Install the Postgres and Redis operators
* Wait for them to be ready
* Deploy the respective PostgresCluster and RedisEnterpriseCluster, RedisDB custom resources

# ARO Pipeline

## 🚀 Azure Red Hat OpenShift (ARO) Pipeline

This project provides a comprehensive CI/CD pipeline for deploying and testing Azure Red Hat OpenShift (ARO) clusters using Tekton. The pipeline automates the entire lifecycle from cluster deployment to endpoint testing and cleanup.

### Infrastructure as Code with Bicep

The project now supports deploying Azure Database for PostgreSQL and Azure Cache for Redis directly through Bicep templates, providing better infrastructure-as-code practices and consistent deployment.

#### Quick Deployment with Bicep

```bash
# Set required environment variables
export CLIENT_ID="your-azure-client-id"
export CLIENT_SECRET="your-azure-client-secret"
export PULL_SECRET='{"auths":{"registry.redhat.io":{"auth":"..."}}}'

# Create PostgreSQL admin password secret
oc create secret generic azure-postgres-admin-password \
  --from-literal=password="your-secure-password"

# Deploy ARO with Azure services
make aro-deploy-test
```

#### Bicep Configuration

The Bicep templates support the following parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `deployPostgres` | Deploy Azure Database for PostgreSQL | `true` | ❌ |
| `deployRedis` | Deploy Azure Cache for Redis | `true` | ❌ |
| `postgresAdminPassword` | PostgreSQL admin password | - | ✅ (if PostgreSQL enabled) |
| `postgresSkuName` | PostgreSQL SKU (dev mode: Standard_B1ms) | `Standard_B1ms` | ❌ |
| `postgresTier` | PostgreSQL tier (dev mode: Burstable) | `Burstable` | ❌ |
| `redisSku` | Redis SKU (dev mode: Basic) | `Basic` | ❌ |
| `redisSize` | Redis size (dev mode: C0) | `C0` | ❌ |

#### Using Makefile with Bicep

```bash
# Create PostgreSQL admin password secret first
oc create secret generic azure-postgres-admin-password \
  --from-literal=password="your-secure-password"

# Deploy ARO with Azure services
make aro-deploy-test POSTGRES_ADMIN_PASSWORD="your-password"

# Get Azure services information
make aro-services-info

# Deploy only ARO (without Azure services - modify test parameters)
make aro-deploy-test POSTGRES_ADMIN_PASSWORD="your-password"
```

## Pipeline Structure

The ARO pipeline consists of several Tekton tasks and a complete pipeline definition. **Azure services (PostgreSQL and Redis) are now deployed via Bicep templates** as part of the ARO deployment, providing better infrastructure-as-code practices.

#### Pipeline Tasks

| Task Name | Purpose | Location |
|-----------|---------|----------|
| `aro-deploy-test` | Deploys ARO cluster with cost-optimized test settings | `.tekton/tasks/aro-deploy-task.yaml` |
| `aro-validate-and-get-access` | Validates cluster, generates kubeconfig, and retrieves Azure services info | `.tekton/tasks/aro-validate-and-get-access-task.yaml` |
| `aro-teardown` | Cleans up ARO cluster and resources | `.tekton/tasks/aro-teardown-task.yaml` |
| `aro-cleanup-failed` | Handles cleanup of failed deployments | `.tekton/tasks/aro-cleanup-failed-task.yaml` |

#### Pipeline Definition

The complete pipeline is defined in `.tekton/pipelines/aro-endpoint-test-pipeline.yaml` and includes:

1. **Repository Fetch**: Clones the source code
2. **ARO Deployment**: Creates ARO cluster with Azure services via Bicep
3. **Cluster Validation & Access**: Validates cluster readiness, generates kubeconfig, and retrieves Azure services information
4. **Manual Approval**: Pause for review before testing
5. **Endpoint Testing**: Runs comprehensive API endpoint tests
6. **Rate Limit Testing**: Validates rate limiting functionality
7. **Manual Approval**: Pause for review before cleanup
8. **Cluster Teardown**: Removes all ARO resources (Azure services cleaned up automatically)

## Prerequisites for ARO Pipeline

Before running the ARO pipeline, ensure you have:

1. **Azure Subscription**: With appropriate permissions for ARO deployment
2. **Domain Zone**: DNS zone configured in Azure for your domain
3. **Kubernetes Secrets**: Required secrets created in your OpenShift project

#### Required Secrets

##### 1. Azure Service Principal Secret

Create a secret containing your Azure service principal credentials, ARO resource group, and ARO domain:

```bash
# Method 1: Using oc with literal values
oc create secret generic azure-sp-secret \
  --from-literal=CLIENT_ID="your-client-id" \
  --from-literal=CLIENT_SECRET="your-client-secret" \
  --from-literal=TENANT_ID="your-tenant-id" \
  --from-literal=ARO_RESOURCE_GROUP="your-aro-resource-group" \
  --from-literal=ARO_DOMAIN="your-domain.com"

# Method 2: Using YAML file
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: azure-sp-secret
type: Opaque
stringData:
  CLIENT_ID: "your-client-id"
  CLIENT_SECRET: "your-client-secret"
  TENANT_ID: "your-tenant-id"
  ARO_RESOURCE_GROUP: "your-aro-resource-group"
  ARO_DOMAIN: "your-domain.com"
EOF
```

##### 2. Red Hat Pull Secret

Create a secret containing your Red Hat pull secret:

```bash
# Method 1: Using oc with file
oc create secret generic redhat-pull-secret \
  --from-file=PULL_SECRET=path/to/pull-secret.txt

# Method 2: Using oc with literal (single line JSON)
oc create secret generic redhat-pull-secret \
  --from-literal=PULL_SECRET='{"auths":{"registry.redhat.io":{"auth":"..."}}}'

# Method 3: Using YAML file
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: redhat-pull-secret
type: Opaque
stringData:
  PULL_SECRET: |
    {
      "auths": {
        "registry.redhat.io": {
          "auth": "your-base64-encoded-auth"
        }
      }
    }
EOF
```

##### 3. EIC Authentication Secret

Create a secret for EIC gateway authentication:

```bash
# Method 1: Using oc with literal values
oc create secret generic eic-auth-secret \
  --from-literal=authKey="your-eic-auth-key"

# Method 2: Using YAML file
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: eic-auth-secret
type: Opaque
stringData:
  authKey: "your-eic-auth-key"
EOF
```

##### 4. PostgreSQL Admin Password Secret

Create a secret containing the PostgreSQL admin password for Azure Database. This secret is mounted directly as an environment variable in the pipeline:

```bash
# Method 1: Using oc with literal values
oc create secret generic azure-postgres-admin-password \
  --from-literal=password="your-secure-postgres-password"

# Method 2: Using YAML file
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: azure-postgres-admin-password
type: Opaque
stringData:
  password: "your-secure-postgres-password"
EOF
```

**Note**: The secret must contain a key named `password` which will be available as the `$POSTGRES_ADMIN_PASSWORD` environment variable in the pipeline.

##### 5. Azure Services Configuration (Optional)

Azure services (PostgreSQL and Redis) are now deployed via Bicep templates as part of the ARO deployment. The PostgreSQL admin password is mounted directly as an environment variable from a Kubernetes secret and passed to the Bicep deployment.

**Note**: If you want to deploy Azure services via Bicep, ensure your Azure service principal has the necessary permissions to create PostgreSQL and Redis resources.

## Running the ARO Pipeline

#### Option 1: Using the Pipeline Template

1. **Copy the pipeline run template**:
   ```bash
   cp .tekton/aro-endpoint-test-run.yaml .tekton/my-aro-test-run.yaml
   ```

2. **Edit the pipeline parameters**:
   ```yaml
   params:
     - name: repoUrl
       value: "https://github.com/redhat-sap/sap-edge.git"
     - name: revision
       value: "main"
     - name: aroClusterName
       value: "my-aro-cluster"
     - name: aroVersion
       value: "4.15.35"
     - name: azureSecretName
       value: "azure-sp-secret"
     - name: pullSecretName
       value: "redhat-pull-secret"
     - name: eicAuthSecretName
       value: "eic-auth-secret"
     - name: postgresAdminPasswordSecretName
       value: "azure-postgres-admin-password"
     - name: deployPostgres
       value: "true"
     - name: deployRedis
       value: "true"
     - name: publicDNS
       value: "false"
   ```
   
   **Note**: `aroResourceGroup` and `aroDomain` are now configured in the `azure-sp-secret` instead of as parameters.

3. **Apply the pipeline run**:
   ```bash
   oc apply -f .tekton/my-aro-test-run.yaml
   ```

#### Option 2: Manual Task Execution

You can also run individual tasks manually by creating TaskRuns:

```bash
# First, apply the task definitions
oc apply -f .tekton/tasks/aro-deploy-task.yaml
oc apply -f .tekton/tasks/aro-validate-and-get-access-task.yaml
oc apply -f .tekton/tasks/aro-teardown-task.yaml

# Then create TaskRuns (example for deploy task)
cat <<EOF | oc apply -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: aro-deploy-
spec:
  taskRef:
    name: aro-deploy
  params:
    - name: aroClusterName
      value: "my-aro-cluster"
    - name: azureSecretName
      value: "azure-sp-secret"
    - name: pullSecretName
      value: "redhat-pull-secret"
  workspaces:
    - name: source
      emptyDir: {}
EOF

# Note: aroResourceGroup and aroDomain are now in the azure-sp-secret
```

## Pipeline Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `repoUrl` | Git repository URL | - | ✅ |
| `revision` | Git branch/tag/commit | - | ✅ |
| `aroLocation` | Azure region | `northeurope` | ❌ |
| `aroClusterName` | ARO cluster name | - | ✅ |
| `aroVersion` | OpenShift version | `4.15.35` | ❌ |
| `azureSecretName` | Azure credentials secret (includes resource group & domain) | `azure-sp-secret` | ❌ |
| `pullSecretName` | Red Hat pull secret | `redhat-pull-secret` | ❌ |
| `eicAuthSecretName` | EIC auth secret | - | ✅ |
| `postgresAdminPasswordSecretName` | Name of the Kubernetes Secret containing PostgreSQL admin password (mounted directly as env var) | `azure-postgres-admin-password` | ✅ (if PostgreSQL enabled) |
| `deployPostgres` | Whether to deploy PostgreSQL (true/false) | `true` | ❌ |
| `deployRedis` | Whether to deploy Redis (true/false) | `true` | ❌ |
| `publicDNS` | Use public DNS resolution | `false` | ❌ |

**Note**: `aroResourceGroup` and `aroDomain` are now stored in the `azureSecretName` secret instead of being passed as parameters.

## Monitoring & Cleanup

The pipeline includes automatic cleanup, but you can also manually clean up resources:

```bash
# Clean up failed deployments
oc apply -f .tekton/tasks/aro-cleanup-failed-task.yaml

# Or use the makefile
make aro-delete-cluster ARO_RESOURCE_GROUP=my-rg ARO_CLUSTER_NAME=my-cluster
make aro-resource-group-delete ARO_RESOURCE_GROUP=my-rg
```

### Monitoring Pipeline Progress

Monitor your pipeline execution:

```bash
# List pipeline runs
oc get pipelineruns

# Watch pipeline progress
oc logs -f pipelinerun/aro-endpoint-test-xxxxx

# Check task status
oc get taskruns
```

### Running Cluster-Specific Endpoint Tests

You can run endpoint tests in two ways:

Option 1: CI/CD via Tekton

This guide explains how to configure and run the automated endpoint test pipeline for your pull request. The pipeline is triggered automatically when the `.tekton/pr-endpoint-run.yaml` file is present in your branch.

#### Prerequisites: Ensuring Secrets Exist

Before the pipeline can run, the OpenShift project where your pipeline executes must contain the necessary secrets. If they do not exist, you will need to create them.

##### 1. Cluster Information ConfigMap and EIC Auth Secret

This configmap holds the configuration for the specific cluster environment you are targeting.

**Example `cluster-info-configmap.yaml`:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
   # The name we will use for our new 'clusterConfigMapName' parameter
   name: cluster-config-bruhl
data:
   # The target hostname (non-sensitive)
   host: "eic.apps.bruhl.ocp.vslen"
   # The ingress IP for internal resolution (non-sensitive)
   ingressIP: "192.168.99.65"
```

The authentication key for the gateway is managed in a separate secret, referenced by the `eicAuthSecretName` parameter in your `PipelineRun`.*
**Example `endpoint-auth-bruhl.yaml`:**
```yaml
apiVersion: v1
kind: Secret
metadata:
   # The name we will use for our new 'eicAuthSecretName' parameter
   name: endpoint-auth-bruhl
type: Opaque
stringData:
   # The auth key to the gateway (sensitive)
   authKey: "your-super-secret-auth-key"
```

**To apply the secret, run:**
```bash
oc apply -f cluster-config-bruhl.yaml -n your-project-namespace
oc apply -f endpoint-auth-bruhl.yaml -n your-project-namespace
```

##### 2. Jira Integration Secret

This secret holds the credentials needed to update a Jira ticket upon successful completion of the pipeline.

**Example `jira-secret.yaml`:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  # The name you will use for the 'jiraSecretName' parameter
  name: jira-credentials
type: Opaque
stringData:
  # The base URL of your Jira instance (e.g., https://your-org.atlassian.net)
  serverURL: "https://your-jira-instance.com"
  # Your Jira API token (NEVER use your password)
  apiToken: "your-super-secret-api-token"
```

**To apply the secret, run:**
```bash
oc apply -f jira-secret.yaml -n your-project-namespace
```

---
#### Pipeline Configuration Steps

##### Step 1: Create and Edit the PipelineRun File

First, copy the pipeline run template into the `.tekton` directory. This file defines the parameters for your specific test run.

```bash
cp .tekton-templates/pr-endpoint-run-bruhl.yaml .tekton/pr-endpoint-run-bruhl.yaml
```

Next, open the newly created `.tekton/pr-endpoint-run.yaml` file and edit the following parameters in the `params` section: 

| Parameter              | Description                                                                                                   | Example Value          |
|------------------------|---------------------------------------------------------------------------------------------------------------|------------------------|
| `clusterConfigMapName` | **(Required)** The name of the Kubernetes ConfigMap containing the `host` and `ingressIP` for your target.    | `"cluster-info-bruhl"` |
| `eicAuthSecretName`    | **(Required)** The name of the Kubernetes Secret containing the authToken for SAP EIC gateway authentication. | `"auth-secret"`        |
| `publicDNS`            | Set to `"true"` to disable `--resolve` and use public DNS. Set to `"false"` for internal resolution.          | `"false"`              |
| `jiraSecretName`       | The name of the Kubernetes Secret containing your Jira `serverURL`, and `apiToken`.                           | `"jira-credentials"`   |
| `jiraIssueKey`         | The Jira ticket key to update with the pipeline results (e.g., PROJ-123).                                     | `"PROJ-456"`           |

##### Step 2: Trigger the Pipeline

Commit and push the `.tekton/pr-endpoint-run.yaml` file as part of your pull request.

```bash
git add .tekton/pr-endpoint-run-bruhl.yaml
git commit -m "feat: Configure endpoint tests for my feature"
git push
```

Once pushed, the OpenShift Pipeline will be triggered automatically. You can view its progress and results directly on your pull request in your Git repository.

#### Option 2: Run Locally

To run the same tests locally (outside the CI/CD pipeline), set the required environment variables and execute the `make test-endpoint` command:

```bash
export HOST=<your-eic-host-name>
export AUTH_KEY=<your-auth-key>
export INGRESS_IP=<your-ingress-ip>

make test-endpoint
```

**Environment Variables:**

* HOST: The target EIC hostname
* AUTH_KEY: Authentication key (as used in the Tekton secret)
* INGRESS_IP: External ingress IP of the cluster

_**Note**: Ensure your test script is configured to read these environment variables. If not, some modifications may be necessary._

## 🛠️ Support & Operations

### Support Information

Red Hat does not provide support for the Postgres/Redis services configured through this repository. Support is available directly from the respective vendors:

- **PostgreSQL**: Crunchy Data offers enterprise-level support for their PostgreSQL Operator through a subscription-based model. This includes various tiers with different response times, service levels, bug fixes, security patches, updates, and technical support. A subscription is required for using the software in third-party consulting or support services. For more details, refer to their [Terms of Use](https://www.crunchydata.com/legal/terms-of-use).

- **Redis**: Support for this solution is provided directly by the Redis Labs team, as detailed in [Appendix 1 of the Redis Enterprise Software Subscription Agreement](https://redislabs.com/wp-content/uploads/2019/11/redis-enterprise-software-subscription-agreement.pdf). The agreement categorizes support services into Support Services, Customer Success Services, and Consulting Services, offering assistance from basic troubleshooting to advanced consultancy and ongoing optimization tailored to diverse customer needs.

For comprehensive support, please contact [Crunchy Data](https://www.crunchydata.com/contact) and [Redis Labs](https://redis.io/meeting/) directly.

### Operations Documentation

For operational guidance on Crunchy Postgres and Redis, refer to the official documentation:

- [Redis on Kubernetes](https://redis.io/docs/latest/operate/kubernetes/)
- [Crunchy Postgres Operator Quickstart](https://access.crunchydata.com/documentation/postgres-operator/latest/quickstart)

### Troubleshooting

#### Common Issues

1. **Pipeline Stuck on Manual Approval**
   ```bash
   # Check approval task status
   oc get taskruns | grep approval
   
   # Approve manually (if using approval task)
   oc patch taskrun <approval-taskrun-name> --type merge -p '{"spec":{"status":"TaskRunCancelled"}}'
   ```

2. **Secret Not Found Errors**
   ```bash
   # Verify secrets exist
   oc get secrets | grep -E "(azure-sp-secret|redhat-pull-secret|eic-auth-secret)"
   
   # Check secret contents
   oc describe secret azure-sp-secret
   ```

3. **ARO Deployment Timeout**
   ```bash
   # Check ARO cluster status in Azure
   az aro show --name <cluster-name> --resource-group <rg-name> --query provisioningState
   
   # Check pipeline logs
   oc logs -f pipelinerun/<pipeline-run-name>
   ```

# License

This project is licensed under the Apache License 2.0. See the [LICENSE](https://www.apache.org/licenses/LICENSE-2.0) for details.