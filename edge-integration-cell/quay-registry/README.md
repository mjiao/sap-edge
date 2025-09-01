# Quay Registry Deployment

This directory contains manifests for deploying Red Hat Quay registry on OpenShift.

## Quick Start

### ARO Deployment with Azure Storage
```bash
# 1. Create Azure storage account for Quay
make aro-quay-storage-create

# 2. Set storage environment variables (displayed by previous command)
export AZURE_STORAGE_ACCOUNT_NAME=quaysapeic123456
export AZURE_STORAGE_ACCOUNT_KEY=your-key-here
export AZURE_STORAGE_CONTAINER=quay-registry

# 3. Complete Quay deployment (includes deployment, wait, and trust configuration)
make aro-quay-deploy-complete

# 4. Create admin user (requires QUAY_ADMIN_PASSWORD and QUAY_ADMIN_EMAIL environment variables)
export QUAY_ADMIN_PASSWORD="your-secure-password"
export QUAY_ADMIN_EMAIL="your-email@sap.com"
make aro-quay-create-admin

# 5. Verify trust configuration is working
make aro-quay-verify-trust

# 6. Test login
make aro-quay-test-login
```

### Step-by-Step ARO Deployment (for advanced users)
If you prefer to run individual steps instead of the complete deployment:

```bash
# Individual deployment steps
make aro-quay-deploy         # Deploy operator and instance
make aro-quay-wait-ready     # Wait for readiness
make aro-quay-trust-cert     # Configure certificate trust
make aro-quay-verify-trust   # Verify trust configuration
make aro-quay-info           # Get connection information
make aro-quay-create-admin   # Create admin user
make aro-quay-status         # Check overall status
```

### Generic Deployment (any OpenShift cluster)
```bash
# Deploy Quay registry on current oc context
make quay-deploy-generic

# Get connection information
make quay-info-generic

# Manual admin user creation and certificate configuration required
```

### Future ROSA Support
When ROSA support is added, similar targets will be available:
- `make rosa-quay-deploy`
- `make rosa-quay-info`
- `make rosa-quay-create-admin`
- etc.

## Environment Variables

Required for Azure storage:
- `AZURE_STORAGE_ACCOUNT_NAME`: Azure storage account name
- `AZURE_STORAGE_ACCOUNT_KEY`: Azure storage account access key  
- `AZURE_STORAGE_CONTAINER`: Azure storage container name (default: quay-registry)

Required for admin user creation:
- `QUAY_ADMIN_PASSWORD`: Password for quayadmin user
- `QUAY_ADMIN_EMAIL`: Email for quayadmin user

## Storage Management

### Azure Storage (Default Configuration)
The current configuration uses Azure Blob Storage for container image storage. The storage account is automatically created with:
- Standard_LRS replication
- Hot access tier  
- Dedicated container for Quay registry data

### Alternative Storage Options
To use external S3 storage instead, modify `quay-config-secret.yaml`:

```yaml
DISTRIBUTED_STORAGE_CONFIG:
  s3Storage:
    - S3Storage
    - host: s3.eu-west-2.amazonaws.com
      s3_access_key: YOUR_ACCESS_KEY
      s3_secret_key: YOUR_SECRET_KEY
      s3_region: eu-west-1
      s3_bucket: your_bucket_name
      storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
  - s3Storage
```

## Testing Access

After deployment and configuration:

```bash
# Get registry endpoint
make quay-info

# Test login (replace with actual endpoint)
podman login your-registry-endpoint/quayadmin
# or
docker login your-registry-endpoint/quayadmin
```

## Troubleshooting

### Certificate Trust Issues
If OpenShift can't pull images from Quay after deployment:

```bash
# Check if trust is configured
make aro-quay-verify-trust

# Check node status (nodes may need restart to pick up CA bundle)
oc get nodes -o wide
oc get mcp -o wide

# If needed, trigger machine config update
oc patch mcp worker --type merge -p '{"spec":{"paused":false}}'

# Wait for nodes to restart and become Ready
oc get nodes -w
```

### Common Issues
1. **"x509: certificate signed by unknown authority"**: Trust configuration not applied or nodes not restarted
2. **"connection refused"**: Quay not ready yet, run `make aro-quay-wait-ready`
3. **"endpoint not found"**: Quay deployment failed, check `make aro-quay-status`

### Manual Certificate Trust (if automation fails)
```bash
# Get registry hostname
REGISTRY=$(oc get quayregistry test-registry -o json | jq -r '.status.registryEndpoint' | sed 's/^https:\/\///')

# Extract CA certificate
oc get -n openshift-ingress-operator -o json secret/router-ca | \
  jq -r '.data as $d | $d | keys[] | select(test("\\.(?:crt|pem)$")) | $d[.] | @base64d' > quay-ca.crt

# Create or update ConfigMap
oc create configmap -n openshift-config trusted-registry-cabundles \
  --from-literal="${REGISTRY//:/..}=$(cat quay-ca.crt)" \
  --dry-run=client -o yaml | oc apply -f -

# Update cluster configuration
oc patch images.config.openshift.io cluster --type=merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"trusted-registry-cabundles"}}}'
```

## Cleanup

```bash
# Delete Quay registry and operator
make aro-quay-delete

# Delete Azure storage (optional, will lose all registry data)
make aro-quay-storage-delete
```