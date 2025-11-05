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
DRY_RUN=false
FORCE=false
VERBOSE=false

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

Cleanup PostgreSQL external services deployed via Crunchy Data Operator.

OPTIONS:
    -n, --namespace NAMESPACE    Namespace to cleanup (default: sap-eic-external-postgres)
    -f, --force                  Skip confirmation prompts (for automation)
    -d, --dry-run               Show what would be deleted without actually deleting
    -v, --verbose               Enable verbose output
    -h, --help                  Display this help message

EXAMPLES:
    # Interactive cleanup with confirmation
    $0

    # Force cleanup without prompts (CI/CD)
    $0 --force

    # Dry-run to see what would be deleted
    $0 --dry-run

    # Cleanup custom namespace
    $0 --namespace my-postgres-namespace

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

# Confirmation prompt
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    log WARNING "This will delete all PostgreSQL resources in namespace: $NAMESPACE"
    echo -e "${YELLOW}Resources to be deleted:${NC}"
    echo "  - PostgresCluster CRs"
    echo "  - Crunchy Postgres Operator subscription"
    echo "  - Crunchy Postgres Operator CSV"
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

log INFO "Starting PostgreSQL cleanup for namespace: $NAMESPACE"

# Step 1: Delete PostgresCluster CRs
log INFO "Step 1/5: Checking for PostgresCluster resources..."
if oc get postgrescluster -n "$NAMESPACE" &> /dev/null; then
    POSTGRES_CLUSTERS=$(oc get postgrescluster -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$POSTGRES_CLUSTERS" ]]; then
        log INFO "Found PostgresCluster resources: $POSTGRES_CLUSTERS"
        for cluster in $POSTGRES_CLUSTERS; do
            execute "oc delete postgrescluster $cluster -n $NAMESPACE"
        done
        
        # Wait for deletion if not dry-run
        if [[ "$DRY_RUN" != "true" ]] && [[ -f "$SCRIPT_DIR/external-postgres/wait_for_deletion_of_postgrescluster.sh" ]]; then
            log INFO "Waiting for PostgresCluster deletion to complete..."
            bash "$SCRIPT_DIR/external-postgres/wait_for_deletion_of_postgrescluster.sh"
        fi
    else
        log INFO "No PostgresCluster resources found."
    fi
else
    log INFO "No PostgresCluster CRD found. Skipping..."
fi

# Step 2: Delete Crunchy Postgres Operator subscription
log INFO "Step 2/5: Checking for Crunchy Postgres Operator subscription..."
if oc get subscription crunchy-postgres-operator -n "$NAMESPACE" &> /dev/null; then
    execute "oc delete subscription crunchy-postgres-operator -n $NAMESPACE"
    log SUCCESS "Deleted Crunchy Postgres Operator subscription."
else
    log INFO "No Crunchy Postgres Operator subscription found."
fi

# Step 3: Delete Crunchy Postgres Operator CSV
log INFO "Step 3/5: Checking for Crunchy Postgres Operator CSV..."
CSV_LIST=$(oc get csv -n "$NAMESPACE" --no-headers 2>/dev/null | grep 'postgresoperator' | awk '{print $1}' || echo "")
if [[ -n "$CSV_LIST" ]]; then
    log INFO "Found CSV resources: $CSV_LIST"
    for csv in $CSV_LIST; do
        execute "oc delete csv $csv -n $NAMESPACE"
    done
    log SUCCESS "Deleted Crunchy Postgres Operator CSV."
else
    log INFO "No Crunchy Postgres Operator CSV found."
fi

# Step 4: Wait for CSV deletion if helper script exists
if [[ "$DRY_RUN" != "true" ]] && [[ -f "$SCRIPT_DIR/external-postgres/wait_for_deletion_of_postgres_csv.sh" ]]; then
    log INFO "Step 4/5: Waiting for CSV deletion to complete..."
    bash "$SCRIPT_DIR/external-postgres/wait_for_deletion_of_postgres_csv.sh" || log WARNING "CSV deletion wait script failed or timed out."
else
    log INFO "Step 4/5: Skipping CSV deletion wait (dry-run or script not found)."
fi

# Step 5: Delete namespace
log INFO "Step 5/5: Deleting namespace: $NAMESPACE..."
execute "oc delete namespace $NAMESPACE"

if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "=== DRY-RUN COMPLETE: No resources were actually deleted ==="
else
    log SUCCESS "PostgreSQL cleanup completed successfully!"
    log INFO "Namespace '$NAMESPACE' and all PostgreSQL resources have been removed."
fi

