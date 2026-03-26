#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Workaround for Hypershift KubeVirt bug on OpenShift 4.21 where the
# service-sync controller fails to create EndpointSlice objects for
# LoadBalancer services in the guest cluster, breaking MetalLB ingress routing.
#
# Usage:
#   ./hack/fix-endpointslice.sh <management-namespace> [guest-service-name]
#
# Example:
#   ./hack/fix-endpointslice.sh clusters-hcp-kv-pr42
#   ./hack/fix-endpointslice.sh clusters-hcp-kv-pr42 istio-ingressgateway

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <management-namespace> [guest-service-name]"
  echo ""
  echo "  management-namespace:  The control plane namespace (e.g. clusters-<clusterName>)"
  echo "  guest-service-name:    LoadBalancer service name in guest cluster (default: istio-ingressgateway)"
  exit 1
fi

MGMT_NS="$1"
GUEST_SVC_NAME="${2:-istio-ingressgateway}"

echo "=========================================="
echo "HCP Fix EndpointSlice"
echo "=========================================="
echo "Management Namespace: ${MGMT_NS}"
echo "Guest Service: ${GUEST_SVC_NAME}"
echo "=========================================="

# Verify oc is available
if ! command -v oc &>/dev/null; then
  echo "❌ 'oc' command not found. Please install OpenShift CLI."
  exit 1
fi

# Verify access
echo ""
echo "🔍 Verifying cluster access..."
oc whoami
echo "✅ Connected"

# Find the management service matching the guest service
echo ""
echo "🔍 Looking for management service matching guest service '${GUEST_SVC_NAME}'..."
MGMT_SVC_NAME=$(oc get svc -n "${MGMT_NS}" \
  -l "cluster.x-k8s.io/tenant-service-name=${GUEST_SVC_NAME}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "${MGMT_SVC_NAME}" ]]; then
  echo "⚠️ Management service not found for guest service '${GUEST_SVC_NAME}'."
  echo "   The guest service may not be deployed yet."
  echo ""
  echo "   Available services in ${MGMT_NS}:"
  oc get svc -n "${MGMT_NS}" --no-headers 2>/dev/null || echo "   (none)"
  exit 1
fi
echo "   Found management service: ${MGMT_SVC_NAME}"

# Check if EndpointSlices already exist
echo ""
echo "🔍 Checking EndpointSlices for ${MGMT_SVC_NAME}..."
SLICE_COUNT=$(oc get endpointslice -n "${MGMT_NS}" \
  -l "kubernetes.io/service-name=${MGMT_SVC_NAME}" \
  -o json | jq '.items | length')

if [[ "${SLICE_COUNT}" -gt 0 ]]; then
  echo "✅ EndpointSlices already exist (${SLICE_COUNT} found). Routing is working."
  oc get endpointslice -n "${MGMT_NS}" -l "kubernetes.io/service-name=${MGMT_SVC_NAME}"
  exit 0
fi

echo "🚨 Bug detected: No EndpointSlices found for ${MGMT_SVC_NAME}. Applying manual fix..."

# Get the targetPort from the management service (https port)
TARGET_PORT=$(oc get svc "${MGMT_SVC_NAME}" -n "${MGMT_NS}" \
  -o jsonpath='{.spec.ports[?(@.name=="https")].targetPort}')

if [[ -z "${TARGET_PORT}" ]]; then
  echo "⚠️ Could not find 'https' port on management service. Trying first port..."
  TARGET_PORT=$(oc get svc "${MGMT_SVC_NAME}" -n "${MGMT_NS}" \
    -o jsonpath='{.spec.ports[0].targetPort}')
fi
echo "   Target port: ${TARGET_PORT}"

# Gather VMI IPs and NodeNames
echo "📋 Gathering VMI endpoints..."
ENDPOINTS_JSON=$(oc get vmi -n "${MGMT_NS}" -o json | jq -c '
  [ .items[] | {
      addresses: [.status.interfaces[0].ipAddress],
      conditions: { ready: true },
      nodeName: .status.nodeName
    }
  ]')

echo "   Endpoints: ${ENDPOINTS_JSON}"

# Apply the EndpointSlice
echo ""
echo "📦 Creating EndpointSlice..."
cat <<EOSLICE | oc apply -f -
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ${MGMT_SVC_NAME}-manual-fix
  namespace: ${MGMT_NS}
  labels:
    kubernetes.io/service-name: ${MGMT_SVC_NAME}
addressType: IPv4
ports:
  - name: https
    port: ${TARGET_PORT}
    protocol: TCP
endpoints: ${ENDPOINTS_JSON}
EOSLICE

echo ""
echo "✅ EndpointSlice created. Verifying..."
oc get endpointslice -n "${MGMT_NS}" -l "kubernetes.io/service-name=${MGMT_SVC_NAME}"

echo ""
echo "=========================================="
echo "✅ Fix applied successfully!"
echo "=========================================="
