#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
NAMESPACE="sap-eic-external-redis"
DRY_RUN=false
FORCE=false
VERBOSE=false
OPENSHIFT_VERSION=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} [${timestamp}] $*"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} [${timestamp}] $*"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} [${timestamp}] $*"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} [${timestamp}] $*"
            ;;
        *)
            echo "[${timestamp}] $*"
            ;;
    esac
}

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Cleanup Redis external services deployed via Redis Enterprise Operator.

OPTIONS:
    -n, --namespace NAMESPACE    Namespace to cleanup (default: sap-eic-external-redis)
    -f, --force                  Skip confirmation prompts (for automation)
    -d, --dry-run               Show what would be deleted without actually deleting
    -v, --verbose               Enable verbose output
    --ocp-version VERSION       Specify OpenShift version (4.16+, <4.16) for SCC cleanup
    -h, --help                  Display this help message

EXAMPLES:
    # Interactive cleanup with confirmation
    $0

    # Force cleanup without prompts (CI/CD)
    $0 --force

    # Dry-run to see what would be deleted
    $0 --dry-run

    # Cleanup with OpenShift version specified
    $0 --ocp-version 4.16

    # Cleanup custom namespace
    $0 --namespace my-redis-namespace

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --ocp-version)
            OPENSHIFT_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log ERROR "Unknown option: $1"
            usage
            ;;
    esac
done

# Verbose mode
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Check if oc is available
if ! command -v oc &> /dev/null; then
    log ERROR "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    log WARNING "Namespace '$NAMESPACE' does not exist. Nothing to cleanup."
    exit 0
fi

# Detect OpenShift version if not provided
if [[ -z "$OPENSHIFT_VERSION" ]]; then
    log INFO "Detecting OpenShift version..."
    OCP_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion // empty' || echo "")
    if [[ -n "$OCP_VERSION" ]]; then
        log INFO "Detected OpenShift version: $OCP_VERSION"
        OPENSHIFT_VERSION="$OCP_VERSION"
    else
        log WARNING "Could not detect OpenShift version. SCC cleanup will be skipped."
        log WARNING "Use --ocp-version flag to specify version manually."
    fi
fi

# Confirmation prompt
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    log WARNING "This will delete all Redis resources in namespace: $NAMESPACE"
    echo -e "${YELLOW}Resources to be deleted:${NC}"
    echo "  - RedisEnterpriseDatabase CRs"
    echo "  - RedisEnterpriseCluster CRs"
    echo "  - Redis Enterprise Operator subscription"
    echo "  - Redis Enterprise Operator CSV"
    echo "  - Redis Enterprise SCC (if OpenShift version detected)"
    echo "  - Namespace: $NAMESPACE"
    echo ""
    read -rp "Are you sure you want to continue? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log INFO "Cleanup cancelled by user."
        exit 0
    fi
fi

# Dry-run header
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "=== DRY-RUN MODE: No resources will be deleted ==="
fi

# Function to execute command
execute() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd"
    else
        log INFO "Executing: $cmd"
        eval "$cmd"
    fi
}

log INFO "Starting Redis cleanup for namespace: $NAMESPACE"

# Step 1: Delete RedisEnterpriseDatabase CRs
log INFO "Step 1/6: Checking for RedisEnterpriseDatabase resources..."
if oc get redisenterprisedatabase -n "$NAMESPACE" &> /dev/null; then
    REDIS_DBS=$(oc get redisenterprisedatabase -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$REDIS_DBS" ]]; then
        log INFO "Found RedisEnterpriseDatabase resources: $REDIS_DBS"
        for db in $REDIS_DBS; do
            execute "oc delete redisenterprisedatabase $db -n $NAMESPACE"
        done
        log SUCCESS "Deleted RedisEnterpriseDatabase resources."
    else
        log INFO "No RedisEnterpriseDatabase resources found."
    fi
else
    log INFO "No RedisEnterpriseDatabase CRD found. Skipping..."
fi

# Step 2: Delete RedisEnterpriseCluster CRs
log INFO "Step 2/6: Checking for RedisEnterpriseCluster resources..."
if oc get redisenterprisecluster -n "$NAMESPACE" &> /dev/null; then
    REDIS_CLUSTERS=$(oc get redisenterprisecluster -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$REDIS_CLUSTERS" ]]; then
        log INFO "Found RedisEnterpriseCluster resources: $REDIS_CLUSTERS"
        for cluster in $REDIS_CLUSTERS; do
            execute "oc delete redisenterprisecluster $cluster -n $NAMESPACE"
        done
        
        # Wait for deletion if not dry-run
        if [[ "$DRY_RUN" != "true" ]] && [[ -f "$SCRIPT_DIR/external-redis/wait_for_deletion_of_rec.sh" ]]; then
            log INFO "Waiting for RedisEnterpriseCluster deletion to complete..."
            bash "$SCRIPT_DIR/external-redis/wait_for_deletion_of_rec.sh"
        fi
    else
        log INFO "No RedisEnterpriseCluster resources found."
    fi
else
    log INFO "No RedisEnterpriseCluster CRD found. Skipping..."
fi

# Step 3: Delete Redis Enterprise Operator subscription
log INFO "Step 3/6: Checking for Redis Enterprise Operator subscription..."
if oc get subscription redis-enterprise-operator-cert -n "$NAMESPACE" &> /dev/null; then
    execute "oc delete subscription redis-enterprise-operator-cert -n $NAMESPACE"
    log SUCCESS "Deleted Redis Enterprise Operator subscription."
else
    log INFO "No Redis Enterprise Operator subscription found."
fi

# Step 4: Delete Redis Enterprise Operator CSV
log INFO "Step 4/6: Checking for Redis Enterprise Operator CSV..."
CSV_LIST=$(oc get csv -n "$NAMESPACE" --no-headers 2>/dev/null | grep 'redis-enterprise-operator' | awk '{print $1}' || echo "")
if [[ -n "$CSV_LIST" ]]; then
    log INFO "Found CSV resources: $CSV_LIST"
    for csv in $CSV_LIST; do
        execute "oc delete csv $csv -n $NAMESPACE"
    done
    log SUCCESS "Deleted Redis Enterprise Operator CSV."
else
    log INFO "No Redis Enterprise Operator CSV found."
fi

# Step 5: Wait for CSV deletion if helper script exists
if [[ "$DRY_RUN" != "true" ]] && [[ -f "$SCRIPT_DIR/external-redis/wait_for_deletion_of_redis_csv.sh" ]]; then
    log INFO "Step 5/6: Waiting for CSV deletion to complete..."
    bash "$SCRIPT_DIR/external-redis/wait_for_deletion_of_redis_csv.sh" || log WARNING "CSV deletion wait script failed or timed out."
else
    log INFO "Step 5/6: Skipping CSV deletion wait (dry-run or script not found)."
fi

# Step 6: Delete Redis Enterprise SCC
log INFO "Step 6/6: Checking for Redis Enterprise SCC..."
if [[ -n "$OPENSHIFT_VERSION" ]]; then
    # Determine SCC name based on OpenShift version
    if [[ "$OPENSHIFT_VERSION" =~ ^4\.([0-9]+) ]]; then
        MINOR_VERSION="${BASH_REMATCH[1]}"
        if [[ "$MINOR_VERSION" -ge 16 ]]; then
            SCC_NAME="redis-enterprise-scc-v2"
        else
            SCC_NAME="redis-enterprise-scc"
        fi
        
        if oc get scc "$SCC_NAME" &> /dev/null; then
            execute "oc delete scc $SCC_NAME"
            log SUCCESS "Deleted Redis Enterprise SCC: $SCC_NAME"
        else
            log INFO "No Redis Enterprise SCC found: $SCC_NAME"
        fi
    else
        log WARNING "Could not parse OpenShift version. Skipping SCC cleanup."
    fi
else
    log WARNING "OpenShift version not detected. Skipping SCC cleanup."
    log INFO "To cleanup SCC manually, run:"
    log INFO "  oc delete scc redis-enterprise-scc-v2  # For OpenShift 4.16+"
    log INFO "  oc delete scc redis-enterprise-scc     # For OpenShift < 4.16"
fi

# Step 7: Delete namespace
log INFO "Step 7/7: Deleting namespace: $NAMESPACE..."
execute "oc delete namespace $NAMESPACE"

if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "=== DRY-RUN COMPLETE: No resources were actually deleted ==="
else
    log SUCCESS "Redis cleanup completed successfully!"
    log INFO "Namespace '$NAMESPACE' and all Redis resources have been removed."
fi

