#!/bin/bash
# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Enable scheduling on master nodes by setting mastersSchedulable to true
# This allows workloads to be scheduled on master nodes, useful for cost optimization
# in smaller clusters or development environments.

usage() {
    echo "Usage: $0"
    echo "Enable scheduling on OpenShift master nodes"
    echo ""
    echo "This script modifies the cluster scheduler configuration to allow"
    echo "workloads to be scheduled on master nodes. Use with caution in"
    echo "production environments as it may impact cluster stability."
    echo ""
    echo "Prerequisites:"
    echo "- Must be logged into OpenShift cluster with cluster-admin privileges"
    echo "- OpenShift CLI (oc) must be available"
    exit 1
}

validate_requirements() {
    # Check if oc CLI is available
    if ! command -v oc >/dev/null 2>&1; then
        echo "❌ OpenShift CLI (oc) not found. Please install oc CLI." >&2
        exit 1
    fi
    
    # Check if we're logged into a cluster
    if ! oc whoami >/dev/null 2>&1; then
        echo "❌ Not logged into OpenShift cluster. Please login first." >&2
        exit 1
    fi
    
    # Check if we have cluster-admin privileges
    if ! oc auth can-i patch scheduler.config.openshift.io/cluster >/dev/null 2>&1; then
        echo "❌ Insufficient privileges. cluster-admin access required to modify scheduler configuration." >&2
        exit 1
    fi
}

check_current_status() {
    echo "🔍 Checking current master node scheduling status..."
    
    local current_status
    current_status=$(oc get scheduler cluster -o jsonpath='{.spec.mastersSchedulable}' 2>/dev/null || echo "null")
    
    case "${current_status}" in
        "true")
            echo "✅ Master nodes are already schedulable"
            echo "ℹ️  No changes needed"
            return 0
            ;;
        "false")
            echo "⚠️  Master nodes are currently not schedulable"
            echo "🔧 Will enable scheduling on master nodes"
            return 1
            ;;
        "null"|"")
            echo "ℹ️  mastersSchedulable field is not set (default: false)"
            echo "🔧 Will enable scheduling on master nodes"
            return 1
            ;;
        *)
            echo "⚠️  Unexpected mastersSchedulable value: ${current_status}"
            echo "🔧 Will set to true"
            return 1
            ;;
    esac
}

enable_master_scheduling() {
    echo "🔧 Enabling scheduling on master nodes..."
    
    # Patch the scheduler configuration to enable master scheduling
    if oc patch scheduler cluster --type=merge -p '{"spec":{"mastersSchedulable":true}}'; then
        echo "✅ Successfully enabled scheduling on master nodes"
    else
        echo "❌ Failed to enable master node scheduling" >&2
        exit 1
    fi
    
    # Wait a moment for the change to propagate
    sleep 2
    
    # Verify the change
    echo "🔍 Verifying configuration change..."
    local new_status
    new_status=$(oc get scheduler cluster -o jsonpath='{.spec.mastersSchedulable}')
    
    if [[ "${new_status}" == "true" ]]; then
        echo "✅ Configuration verified: mastersSchedulable = ${new_status}"
    else
        echo "❌ Configuration verification failed: mastersSchedulable = ${new_status}" >&2
        exit 1
    fi
}

show_master_nodes() {
    echo ""
    echo "📋 Current master nodes status:"
    oc get nodes -l node-role.kubernetes.io/master= -o wide --show-labels=false || echo "Failed to get master nodes"
    
    echo ""
    echo "ℹ️  Master nodes can now schedule workloads"
    echo "⚠️  Note: This change affects cluster resource allocation and may impact performance"
    echo "💡 Consider adding tolerations to workloads that should run on master nodes"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                ;;
        esac
    done
    
    validate_requirements
    
    if check_current_status; then
        # Already enabled, just show status
        show_master_nodes
        exit 0
    fi
    
    enable_master_scheduling
    show_master_nodes
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi