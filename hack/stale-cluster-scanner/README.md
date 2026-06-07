# Stale Cluster Scanner

A CronJob that scans ARO and ROSA clusters for stale instances older than a configurable threshold and sends a summary report to Slack.

## Files

- `cronjob.yaml` - Kubernetes CronJob and ConfigMap (deploy to OpenShift)
- `scan.sh` - Standalone script (run locally or in CI)
- `Dockerfile` - Container image with pre-installed dependencies (`az`, `rosa`, `jq`)

## Container Image

Pre-built image: `quay.io/redhat-sap-cop/stale-cluster-scanner:latest`

To rebuild:

```bash
docker build --platform linux/amd64 -t quay.io/redhat-sap-cop/stale-cluster-scanner:latest .
docker push quay.io/redhat-sap-cop/stale-cluster-scanner:latest
```

## Deployment

### 1. Create the namespace and secrets

```bash
oc create namespace aro-rosa-checks

oc create secret generic azure-credentials -n aro-rosa-checks \
  --from-literal=client-id='<AZURE_CLIENT_ID>' \
  --from-literal=client-secret='<AZURE_CLIENT_SECRET>' \
  --from-literal=tenant-id='<AZURE_TENANT_ID>' \
  --from-literal=subscription-id='<AZURE_SUBSCRIPTION_ID>'

oc create secret generic aws-credentials -n aro-rosa-checks \
  --from-literal=rosa-token='<ROSA_TOKEN>' \
  --from-literal=access-key-id='<AWS_ACCESS_KEY_ID>' \
  --from-literal=secret-access-key='<AWS_SECRET_ACCESS_KEY>'

oc create secret generic slack-webhook -n aro-rosa-checks \
  --from-literal=webhook-url='<SLACK_WEBHOOK_URL>'
```

### 2. Grant anyuid SCC (required for az CLI)

```bash
oc adm policy add-scc-to-user anyuid -z default -n aro-rosa-checks
```

### 3. Apply the CronJob

```bash
oc apply -f cronjob.yaml
```

### 4. Test with a manual run

```bash
oc create job --from=cronjob/stale-cluster-scanner stale-cluster-scanner-manual -n aro-rosa-checks
oc logs -f -l job-name=stale-cluster-scanner-manual -n aro-rosa-checks
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `THRESHOLD_HOURS` | `24` | Clusters older than this are reported as stale |
| `AWS_DEFAULT_REGION` | `eu-north-1` | AWS region (required by rosa CLI) |

The CronJob runs daily at 08:00 UTC. Edit the `schedule` field in `cronjob.yaml` to change.

## Local Usage

```bash
export AZURE_CLIENT_ID=...
export AZURE_CLIENT_SECRET=...
export AZURE_TENANT_ID=...
export AZURE_SUBSCRIPTION_ID=...
export ROSA_TOKEN=...
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=eu-north-1
export SLACK_WEBHOOK_URL=...

./scan.sh
```
