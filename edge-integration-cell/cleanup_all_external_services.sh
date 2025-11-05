#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CLEANUP_POSTGRES=true
CLEANUP_REDIS=true
POSTGRES_NAMESPACE="sap-eic-external-postgres"
REDIS_NAMESPACE="sap-eic-external-redis"
DRY_RUN=false
FORCE=false
VERBOSE=false
OPENSHIFT_VERSION=""

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

Comprehensive cleanup of all SAP EIC external services (PostgreSQL and Redis).

OPTIONS:
    --postgres-only              Cleanup only PostgreSQL (skip Redis)
    --redis-only                 Cleanup only Redis (skip PostgreSQL)
    --postgres-namespace NS      PostgreSQL namespace (default: sap-eic-external-postgres)
    --redis-namespace NS         Redis namespace (default: sap-eic-external-redis)
    --ocp-version VERSION        Specify OpenShift version for SCC cleanup
    -f, --force                  Skip all confirmation prompts (for automation)
    -d, --dry-run               Show what would be deleted without actually deleting
    -v, --verbose               Enable verbose output
    -h, --help                  Display this help message

EXAMPLES:
    # Interactive cleanup of both PostgreSQL and Redis
    $0

    # Force cleanup without prompts (CI/CD)
    $0 --force

    # Dry-run to see what would be deleted
    $0 --dry-run

    # Cleanup only PostgreSQL
    $0 --postgres-only

    # Cleanup only Redis
    $0 --redis-only

    # Cleanup with OpenShift version specified
    $0 --ocp-version 4.16

    # Cleanup with custom namespaces
    $0 --postgres-namespace my-postgres --redis-namespace my-redis

REQUIREMENTS:
    - oc CLI tool installed and configured
    - Cluster admin access
    - Helper scripts in edge-integration-cell/external-postgres/ and external-redis/

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --postgres-only)
            CLEANUP_POSTGRES=true
            CLEANUP_REDIS=false
            shift
            ;;
        --redis-only)
            CLEANUP_POSTGRES=false
            CLEANUP_REDIS=true
            shift
            ;;
        --postgres-namespace)
            POSTGRES_NAMESPACE="$2"
            shift 2
            ;;
        --redis-namespace)
            REDIS_NAMESPACE="$2"
            shift 2
            ;;
        --ocp-version)
            OPENSHIFT_VERSION="$2"
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

# Display banner
log HEADER "SAP EIC External Services Cleanup Utility"

# Summary of what will be cleaned
log INFO "Cleanup Configuration:"
log INFO "  - PostgreSQL: $([ "$CLEANUP_POSTGRES" == "true" ] && echo "YES (namespace: $POSTGRES_NAMESPACE)" || echo "NO")"
log INFO "  - Redis: $([ "$CLEANUP_REDIS" == "true" ] && echo "YES (namespace: $REDIS_NAMESPACE)" || echo "NO")"
log INFO "  - Dry-run: $([ "$DRY_RUN" == "true" ] && echo "YES" || echo "NO")"
log INFO "  - Force mode: $([ "$FORCE" == "true" ] && echo "YES" || echo "NO")"

# Confirmation prompt
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    log WARNING "⚠️  This operation will DELETE external services. This action cannot be undone!"
    echo -e "${YELLOW}Services to be cleaned:${NC}"
    if [[ "$CLEANUP_POSTGRES" == "true" ]]; then
        echo "  ✗ PostgreSQL (namespace: $POSTGRES_NAMESPACE)"
    fi
    if [[ "$CLEANUP_REDIS" == "true" ]]; then
        echo "  ✗ Redis (namespace: $REDIS_NAMESPACE)"
    fi
    echo ""
    read -rp "Type 'DELETE' to confirm cleanup: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log INFO "Cleanup cancelled by user."
        exit 0
    fi
fi

# Dry-run header
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "════════════════════════════════════════════════════════════════"
    log INFO "                    DRY-RUN MODE ENABLED"
    log INFO "         No resources will be actually deleted"
    log INFO "════════════════════════════════════════════════════════════════"
fi

# Cleanup start time
START_TIME=$(date +%s)

# Track errors
ERRORS=0

# Cleanup PostgreSQL
if [[ "$CLEANUP_POSTGRES" == "true" ]]; then
    log HEADER "Cleaning up PostgreSQL External Services"
    
    POSTGRES_SCRIPT="$SCRIPT_DIR/cleanup_postgres.sh"
    if [[ ! -f "$POSTGRES_SCRIPT" ]]; then
        log ERROR "PostgreSQL cleanup script not found: $POSTGRES_SCRIPT"
        ((ERRORS++))
    else
        CLEANUP_ARGS=(
            "--namespace" "$POSTGRES_NAMESPACE"
        )
        
        if [[ "$DRY_RUN" == "true" ]]; then
            CLEANUP_ARGS+=("--dry-run")
        fi
        
        if [[ "$FORCE" == "true" ]]; then
            CLEANUP_ARGS+=("--force")
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            CLEANUP_ARGS+=("--verbose")
        fi
        
        if bash "$POSTGRES_SCRIPT" "${CLEANUP_ARGS[@]}"; then
            log SUCCESS "PostgreSQL cleanup completed successfully"
        else
            log ERROR "PostgreSQL cleanup failed"
            ((ERRORS++))
        fi
    fi
    echo ""
fi

# Cleanup Redis
if [[ "$CLEANUP_REDIS" == "true" ]]; then
    log HEADER "Cleaning up Redis External Services"
    
    REDIS_SCRIPT="$SCRIPT_DIR/cleanup_redis.sh"
    if [[ ! -f "$REDIS_SCRIPT" ]]; then
        log ERROR "Redis cleanup script not found: $REDIS_SCRIPT"
        ((ERRORS++))
    else
        CLEANUP_ARGS=(
            "--namespace" "$REDIS_NAMESPACE"
        )
        
        if [[ -n "$OPENSHIFT_VERSION" ]]; then
            CLEANUP_ARGS+=("--ocp-version" "$OPENSHIFT_VERSION")
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            CLEANUP_ARGS+=("--dry-run")
        fi
        
        if [[ "$FORCE" == "true" ]]; then
            CLEANUP_ARGS+=("--force")
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            CLEANUP_ARGS+=("--verbose")
        fi
        
        if bash "$REDIS_SCRIPT" "${CLEANUP_ARGS[@]}"; then
            log SUCCESS "Redis cleanup completed successfully"
        else
            log ERROR "Redis cleanup failed"
            ((ERRORS++))
        fi
    fi
    echo ""
fi

# Cleanup end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final summary
log HEADER "Cleanup Summary"
log INFO "Total time: ${DURATION} seconds"

if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "Dry-run completed. No resources were actually deleted."
elif [[ $ERRORS -eq 0 ]]; then
    log SUCCESS "✅ All cleanup operations completed successfully!"
else
    log ERROR "⚠️  Cleanup completed with $ERRORS error(s)."
    exit 1
fi

