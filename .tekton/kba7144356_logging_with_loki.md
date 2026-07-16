# Collecting SAP Edge Integration Cell Logs with OpenShift Logging and LokiStack

> **Part of:** [SAP Edge Integration Cell on Red Hat OpenShift](https://access.redhat.com/articles/7084706)

### **Table of Contents**

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Step 1: Create the Object Storage Secret](#logging-storage)
* [Step 2: Deploy LokiStack](#deploy-lokistack)
* [Step 3: Create the Log Collector ServiceAccount](#logging-serviceaccount)
* [Step 4: Deploy ClusterLogForwarder](#deploy-clusterlogforwarder)
* [Step 5: Enable the Console Log Viewer](#enable-console-logging)
* [Verification](#verification)

### **Overview** {#overview}

This guide describes how to set up centralized log collection for **SAP Edge Integration Cell (EIC)** on Red Hat OpenShift using the **Loki Operator** and the **Red Hat OpenShift Logging Operator**. Logs from all EIC namespaces are collected and stored in a LokiStack instance, where they can be searched and filtered through the built-in OpenShift console log viewer (**Observe → Logs**).

Use this guide as a starting point and adapt the configuration to your environment and operational requirements.

> **Note:** If your organization already has a centralized logging platform (e.g., Splunk, Elasticsearch, Amazon CloudWatch, or Kafka), you can use the ClusterLogForwarder to forward logs to those external systems instead of LokiStack. See the [OpenShift Logging documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/logging/logging-6-5#log6x-clf-output-types) for supported output types and configuration examples.

**Intended Audience:** This document is for **Red Hat OpenShift Cluster Administrators** who have already deployed EIC on OpenShift and want to set up centralized log collection for EIC workloads.

### **Prerequisites** {#prerequisites}

Before beginning this setup, ensure you have completed the following requirements:

#### **Required Access and Credentials**

- **Cluster-admin privileges** on the target OpenShift cluster
- **Authenticated `oc` CLI session** to your OpenShift cluster

#### **Existing EIC Deployment**

- **Red Hat OpenShift Container Platform** 4.14+
- **SAP Edge Integration Cell** deployed with all namespaces:
    - `edgelm` — Edge Lifecycle Management
    - `edge-icell` — Main application components
    - `edge-icell-services` — Supporting services
    - `edge-icell-secrets` — Secrets management
    - `edge-icell-ela` — Event Log Agent
    - `istio-gateways` — Service mesh gateway components

#### **Required Operators**

Install the following operators from **OperatorHub** (Operators → OperatorHub) before proceeding:

| Operator | Role | What it provides |
|----------|------|------------------|
| Loki Operator | Log storage | LokiStack — stores and indexes logs for querying |
| Red Hat OpenShift Logging Operator | Log collection | ClusterLogForwarder — collects container logs and forwards them to a log store |

#### **Object Storage**

LokiStack requires S3-compatible object storage. Supported backends include:

- Amazon S3
- MinIO
- Azure Blob Storage
- Google Cloud Storage
- Red Hat OpenShift Data Foundation (ODF)

Have your object storage endpoint, bucket names, and credentials ready before proceeding. This guide uses generic S3-compatible examples — adapt the Secret manifests for your specific backend.

### **Step 1: Create the Object Storage Secret** {#logging-storage}

Create a Secret with your S3-compatible object storage credentials:

~~~
oc apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
stringData:
  endpoint: https://<your-s3-endpoint>
  bucketnames: loki-logs
  access_key_id: <your-access-key>
  access_key_secret: <your-secret-key>
  region: <your-region>
type: Opaque
EOF
~~~

> **Note:** Replace all `<placeholder>` values with your actual object storage details. If using MinIO, the endpoint is typically `http://minio.minio.svc:9000`. For ODF, the NooBaa S3 endpoint is typically `https://s3-openshift-storage.apps.<cluster-domain>` (external) or `https://s3.openshift-storage.svc:443` (cluster-internal). See the [ODF documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/) for details.
>
> If your S3 endpoint uses a certificate signed by a custom or private CA, create a ConfigMap with the CA certificate (key must be `service-ca.crt`) and reference it in the LokiStack `spec.storage.tls.caName` field. See [How to configure Loki Object Storage CA certificate](https://access.redhat.com/solutions/7006107) for details.

### **Step 2: Deploy LokiStack** {#deploy-lokistack}

~~~
oc apply -f - <<EOF
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.small
  storage:
    schemas:
    - version: v13
      effectiveDate: "2024-10-25"
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: <your-storage-class>
  tenants:
    mode: openshift-logging
EOF
~~~

> **Note:** Replace `<your-storage-class>` with your cluster's default StorageClass (e.g., `gp3-csi`, `ocs-storagecluster-ceph-rbd`, `thin-csi`). Run `oc get sc` to list available StorageClasses. The `1x.small` size is suitable for production workloads. For smaller or evaluation clusters with limited CPU and memory, use `1x.extra-small` instead.

Wait for all LokiStack pods to reach `Running` state:

~~~
oc get pods -n openshift-logging -l app.kubernetes.io/instance=logging-loki --watch
~~~

### **Step 3: Create the Log Collector ServiceAccount** {#logging-serviceaccount}

The ClusterLogForwarder requires a ServiceAccount with permissions to collect logs:

~~~
oc create sa eic-log-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-application-logs \
  -z eic-log-collector -n openshift-logging

oc adm policy add-cluster-role-to-user cluster-logging-write-application-logs \
  -z eic-log-collector -n openshift-logging
~~~

### **Step 4: Deploy ClusterLogForwarder** {#deploy-clusterlogforwarder}

Configure log collection from all EIC namespaces, forwarding to LokiStack:

~~~
oc apply -f - <<EOF
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: eic-log-collector
  namespace: openshift-logging
spec:
  serviceAccount:
    name: eic-log-collector
  inputs:
  - name: eic-application-logs
    type: application
    application:
      includes:
      - namespace: edgelm
      - namespace: edge-icell
      - namespace: edge-icell-services
      - namespace: edge-icell-secrets
      - namespace: edge-icell-ela
      - namespace: istio-gateways
  outputs:
  - name: loki-output
    type: lokiStack
    lokiStack:
      target:
        name: logging-loki
        namespace: openshift-logging
      dataModel: Otel
      authentication:
        token:
          from: serviceAccount
    tls:
      ca:
        configMapName: logging-loki-gateway-ca-bundle
        key: service-ca.crt
  pipelines:
  - name: eic-logs-pipeline
    inputRefs:
    - eic-application-logs
    outputRefs:
    - loki-output
EOF
~~~

Configuration notes:
- **`inputs.application.includes`** — Collects logs only from the six EIC namespaces, not the entire cluster.
- **`dataModel: Otel`** — Uses the OpenTelemetry data model for log storage, which provides standardized attribute naming (e.g., `k8s.namespace.name`).
- **`tls.ca`** — References the LokiStack gateway CA bundle so the collector trusts the gateway's service-serving certificate.

### **Step 5: Enable the Console Log Viewer** {#enable-console-logging}

Create a UIPlugin to enable the **Observe → Logs** page in the OpenShift console:

~~~
oc apply -f - <<EOF
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
EOF
~~~

After applying, refresh the OpenShift console. The **Logs** tab will appear under **Observe**.

### **Verification** {#verification}

1. Confirm both operators are installed:

~~~
oc get csv -n openshift-operators | grep -E "loki|logging"
~~~

Both should show `Succeeded`.

2. Confirm LokiStack is ready:

~~~
oc get lokistack logging-loki -n openshift-logging
~~~

3. Confirm the collector pods are running:

~~~
oc get pods -n openshift-logging -l app.kubernetes.io/instance=eic-log-collector
~~~

4. Check the ClusterLogForwarder status:

~~~
oc get clusterlogforwarder eic-log-collector -n openshift-logging -o yaml | grep -A 5 conditions
~~~

All conditions should show `status: "True"`.

5. Verify logs are being ingested by navigating to the OpenShift console → **Observe** → **Logs** and filtering by namespace `edge-icell`. You should see recent log entries from EIC pods.
