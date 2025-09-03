# Ansible-Based Quay Registry Deployment

This directory contains Ansible playbooks for deploying Red Hat Quay registry on OpenShift platforms (ARO and ROSA) with improved reliability, idempotency, and error handling compared to the bash script approach.

## Why Ansible?

### **Problems Solved:**
- ✅ **Complex shell quoting issues** (jq, awk, sed problems)
- ✅ **Template substitution reliability** (Jinja2 vs manual awk)
- ✅ **HTTP API calls with retry logic** (built-in uri module)
- ✅ **Resource waiting and validation** (native k8s modules)
- ✅ **Error handling and rollback** (proper rescue blocks)
- ✅ **Cross-platform consistency** (same playbook for ARO/ROSA)
- ✅ **Idempotent operations** (can run multiple times safely)

### **Key Improvements:**
- **Certificate Trust**: Native k8s resource manipulation instead of shell + jq
- **Configuration**: Jinja2 templating instead of awk substitution
- **Admin User**: HTTP module with retry instead of manual curl loops
- **Resource Waiting**: Built-in k8s waiting instead of custom polling
- **Error Handling**: Structured error handling with rescue blocks

## Prerequisites

### Install Ansible and Dependencies
```bash
# Install Ansible
pip install ansible

# Install required collections
ansible-galaxy collection install -r ansible/requirements.yml
```

### Required Tools
- `oc` CLI logged into your cluster
- Environment variables for storage backend
- Environment variables for Quay admin user

## Usage

### ARO Deployment with Ansible
```bash
# Set required environment variables
export ARO_CLUSTER_NAME="your-cluster"
export AZURE_STORAGE_ACCOUNT_NAME="your-storage-account"
export AZURE_STORAGE_ACCOUNT_KEY="your-key"
export AZURE_STORAGE_CONTAINER="quay-registry"
export QUAY_ADMIN_PASSWORD="your-secure-password"
export QUAY_ADMIN_EMAIL="admin@example.com"

# Deploy with Ansible (recommended)
make aro-quay-deploy

# Or run playbook directly
ansible-playbook ansible/quay-deploy.yml \
  -i ansible/inventory.yml \
  -e platform=aro \
  -e cluster_name="${ARO_CLUSTER_NAME}" \
  -e azure_storage_account_name="${AZURE_STORAGE_ACCOUNT_NAME}" \
  -e azure_storage_account_key="${AZURE_STORAGE_ACCOUNT_KEY}" \
  -e quay_admin_password="${QUAY_ADMIN_PASSWORD}" \
  -e quay_admin_email="${QUAY_ADMIN_EMAIL}"
```

### ROSA Deployment with Ansible
```bash
# Set required environment variables
export CLUSTER_NAME="your-cluster"
export S3_BUCKET_NAME="your-s3-bucket"
export S3_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export QUAY_ADMIN_PASSWORD="your-secure-password"
export QUAY_ADMIN_EMAIL="admin@example.com"

# Deploy with Ansible (recommended)
make rosa-quay-deploy

# Or run playbook directly
ansible-playbook ansible/quay-deploy.yml \
  -i ansible/inventory.yml \
  -e platform=rosa \
  -e cluster_name="${CLUSTER_NAME}" \
  -e s3_bucket_name="${S3_BUCKET_NAME}" \
  -e s3_region="${S3_REGION}" \
  -e aws_access_key_id="${AWS_ACCESS_KEY_ID}" \
  -e aws_secret_access_key="${AWS_SECRET_ACCESS_KEY}" \
  -e quay_admin_password="${QUAY_ADMIN_PASSWORD}" \
  -e quay_admin_email="${QUAY_ADMIN_EMAIL}"
```

## Playbook Structure

```
ansible/
├── quay-deploy.yml              # Main playbook
├── inventory.yml                # Inventory (localhost)
├── requirements.yml             # Ansible collections
└── tasks/
    ├── storage/
    │   ├── aro-storage.yml      # Azure storage validation
    │   └── rosa-storage.yml     # S3 storage validation
    └── quay/
        ├── deploy-operator.yml  # Install Quay operator
        ├── configure-storage.yml # Create config with storage backend
        ├── deploy-registry.yml  # Create QuayRegistry resource
        ├── wait-ready.yml       # Wait for pods and endpoint
        ├── configure-trust.yml  # Configure certificate trust
        ├── create-admin.yml     # Create admin user via API
        └── verify-deployment.yml # Final verification
```

## Tags for Selective Execution

Run specific parts of the deployment:

```bash
# Only configure certificate trust
ansible-playbook ansible/quay-deploy.yml --tags trust

# Only create admin user
ansible-playbook ansible/quay-deploy.yml --tags admin

# Skip certificate trust configuration
ansible-playbook ansible/quay-deploy.yml --skip-tags trust

# Only storage and configuration
ansible-playbook ansible/quay-deploy.yml --tags storage,config
```

## Configuration Variables

### Platform Selection
- `platform`: `aro` or `rosa` (required)

### ARO Variables
- `azure_storage_account_name`: Azure storage account name
- `azure_storage_account_key`: Azure storage account key
- `azure_storage_container`: Container name (default: "quay-registry")

### ROSA Variables
- `s3_bucket_name`: S3 bucket name
- `s3_region`: S3 region
- `s3_host`: S3 endpoint host
- `aws_access_key_id`: AWS access key
- `aws_secret_access_key`: AWS secret key

### Quay Variables
- `quay_admin_password`: Password for admin user (required)
- `quay_admin_email`: Email for admin user (required)
- `cluster_name`: Cluster name for reference

## Troubleshooting

### Certificate Trust Issues
```bash
# Check trust configuration only
make aro-quay-trust-cert

# Manual verification
oc get configmap trusted-registry-cabundles -n openshift-config -o yaml
oc get images.config.openshift.io cluster -o yaml
```

### Admin User Creation Issues
```bash
# Check Quay pods status
oc get pods -n openshift-operators | grep test-registry

# Check Quay logs
oc logs -n openshift-operators -l quay-component=quay-app

# Test endpoint manually
curl -k https://your-quay-endpoint/health/instance
```

### Storage Configuration Issues
```bash
# Verify storage variables are set
ansible-playbook ansible/quay-deploy.yml --tags storage -v

# Check Quay config secret
oc get secret config-bundle-secret -n openshift-operators -o yaml
```

## Advantages Over Bash Scripts

1. **Reliability**: Native k8s modules instead of shell + jq
2. **Templating**: Jinja2 instead of error-prone awk/sed
3. **Idempotency**: Can run multiple times safely
4. **Error Handling**: Structured rescue blocks
5. **Readability**: Clear task structure vs complex shell scripts
6. **Debugging**: Built-in verbose mode and task-level debugging
7. **Testing**: Can be tested with `--check` mode
8. **Cross-platform**: Same playbook works for ARO and ROSA

## Migration from Bash Scripts

**Old approach:**
```bash
make aro-quay-deploy-complete
```

**New approach:**
```bash
make aro-quay-deploy 
```

The Ansible implementation provides the same functionality with better reliability and maintainability.