#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
NAMESPACE="sap-eic-external-postgres"
POSTGRES_VERSION="v17"
DRY_RUN=false
FORCE=false
VERBOSE=false
SKIP_WAIT=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
        HEADER)
            echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC} $*"
            echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
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

Deploy PostgreSQL external service using Crunchy Data Operator.

OPTIONS:
    -n, --namespace NAMESPACE    Namespace for deployment (default: sap-eic-external-postgres)
    -v, --version VERSION        PostgreSQL version: v15, v16, v17 (default: v17)
    -f, --force                  Skip confirmation prompts (for automation)
    -d, --dry-run               Show what would be deployed without actually deploying
    --skip-wait                  Skip waiting for operator/cluster readiness
    --verbose                    Enable verbose output
    -h, --help                  Display this help message

EXAMPLES:
    # Interactive deployment with default settings
    $0

    # Deploy PostgreSQL v16 to custom namespace
    $0 --namespace my-postgres --version v16

    # Force deployment without prompts (CI/CD)
    $0 --force

    # Dry-run to preview deployment
    $0 --dry-run

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
        -v|--version)
            POSTGRES_VERSION="$2"
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
        --skip-wait)
            SKIP_WAIT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
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

# Validate PostgreSQL version
if [[ ! "$POSTGRES_VERSION" =~ ^v1[5-7]$ ]]; then
    log ERROR "Invalid PostgreSQL version: $POSTGRES_VERSION. Must be v15, v16, or v17."
    exit 1
fi

# Check if oc is available
if ! command -v oc &> /dev/null; then
    log ERROR "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if already deployed
if oc get namespace "$NAMESPACE" &> /dev/null; then
    log WARNING "Namespace '$NAMESPACE' already exists."
    if oc get postgrescluster -n "$NAMESPACE" &> /dev/null 2>&1; then
        EXISTING_CLUSTERS=$(oc get postgrescluster -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        if [[ -n "$EXISTING_CLUSTERS" ]]; then
            log ERROR "PostgresCluster(s) already exist: $EXISTING_CLUSTERS"
            log ERROR "Please run cleanup first: bash $SCRIPT_DIR/cleanup_postgres.sh"
            exit 1
        fi
    fi
fi

# Display banner
log HEADER "PostgreSQL External Service Deployment"

# Summary
log INFO "Deployment Configuration:"
log INFO "  - Namespace: $NAMESPACE"
log INFO "  - PostgreSQL Version: $POSTGRES_VERSION"
log INFO "  - Dry-run: $([ "$DRY_RUN" == "true" ] && echo "YES" || echo "NO")"
log INFO "  - Skip wait: $([ "$SKIP_WAIT" == "true" ] && echo "YES" || echo "NO")"

# Confirmation prompt
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    log WARNING "This will deploy PostgreSQL operator and cluster to: $NAMESPACE"
    echo ""
    read -rp "Do you want to continue? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log INFO "Deployment cancelled by user."
        exit 0
    fi
fi

# Dry-run header
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "════════════════════════════════════════════════════════════════"
    log INFO "                    DRY-RUN MODE ENABLED"
    log INFO "           No resources will be actually deployed"
    log INFO "════════════════════════════════════════════════════════════════"
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

# Deployment start time
START_TIME=$(date +%s)

log INFO "Starting PostgreSQL deployment..."

# Step 1: Create namespace
log INFO "Step 1/7: Creating namespace: $NAMESPACE"
if [[ "$DRY_RUN" != "true" ]]; then
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        execute "oc create namespace $NAMESPACE"
        log SUCCESS "Namespace created."
    else
        log INFO "Namespace already exists."
    fi
else
    log INFO "[DRY-RUN] Would create namespace"
fi

# Step 2: Apply OperatorGroup
log INFO "Step 2/7: Applying OperatorGroup configuration..."
execute "oc apply -f $SCRIPT_DIR/postgres-operator/operatorgroup.yaml"

# Step 3: Apply Subscription
log INFO "Step 3/7: Applying Subscription configuration..."
execute "oc apply -f $SCRIPT_DIR/postgres-operator/subscription.yaml"

# Step 4: Wait for operator to be ready
if [[ "$SKIP_WAIT" != "true" && "$DRY_RUN" != "true" ]]; then
    log INFO "Step 4/7: Waiting for Postgres operator to be ready..."
    if [[ -f "$SCRIPT_DIR/external-postgres/wait_for_postgres_operator_ready.sh" ]]; then
        bash "$SCRIPT_DIR/external-postgres/wait_for_postgres_operator_ready.sh"
        log SUCCESS "Postgres operator is ready."
    else
        log WARNING "Wait script not found. Sleeping 60s..."
        sleep 60
    fi
else
    log INFO "Step 4/7: Skipping operator readiness wait."
fi

# Step 5: Create PostgresCluster
log INFO "Step 5/7: Creating PostgresCluster ($POSTGRES_VERSION)..."
POSTGRES_CLUSTER_FILE="$SCRIPT_DIR/external-postgres/postgrescluster-${POSTGRES_VERSION}.yaml"
if [[ ! -f "$POSTGRES_CLUSTER_FILE" ]]; then
    log ERROR "PostgresCluster file not found: $POSTGRES_CLUSTER_FILE"
    exit 1
fi
execute "oc apply -f $POSTGRES_CLUSTER_FILE"

# Step 6: Wait for PostgresCluster to be ready
if [[ "$SKIP_WAIT" != "true" && "$DRY_RUN" != "true" ]]; then
    log INFO "Step 6/7: Waiting for PostgresCluster to be ready..."
    if [[ -f "$SCRIPT_DIR/external-postgres/wait_for_postgres_ready.sh" ]]; then
        bash "$SCRIPT_DIR/external-postgres/wait_for_postgres_ready.sh"
        log SUCCESS "PostgresCluster is ready."
    else
        log WARNING "Wait script not found. Sleeping 120s..."
        sleep 120
    fi
else
    log INFO "Step 6/7: Skipping PostgresCluster readiness wait."
fi

# Step 7: Get access details
if [[ "$DRY_RUN" != "true" ]]; then
    log INFO "Step 7/7: Retrieving PostgreSQL access details..."
    echo ""
    if [[ -f "$SCRIPT_DIR/external-postgres/get_external_postgres_access.sh" ]]; then
        bash "$SCRIPT_DIR/external-postgres/get_external_postgres_access.sh"
    else
        log WARNING "Access script not found. You can retrieve access details manually later."
    fi
else
    log INFO "Step 7/7: [DRY-RUN] Would retrieve access details."
fi

# Deployment end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final summary
echo ""
log HEADER "Deployment Summary"
log INFO "Total time: ${DURATION} seconds"

if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "Dry-run completed. No resources were actually deployed."
else
    log SUCCESS "✅ PostgreSQL deployment completed successfully!"
    log INFO "Namespace: $NAMESPACE"
    log INFO "Version: $POSTGRES_VERSION"
    echo ""
    log INFO "Next steps:"
    log INFO "  1. Use the access details above to configure SAP EIC"
    log INFO "  2. To cleanup: bash $SCRIPT_DIR/cleanup_postgres.sh"
fi

