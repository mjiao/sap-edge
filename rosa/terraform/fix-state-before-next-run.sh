#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# fix-state-before-next-run.sh
# Fixes Terraform state when ROSA cluster was deleted outside of Terraform
# This removes stale resources from state so the next deployment can proceed

set -e

CLUSTER_NAME=${1:-"sap-eic-rosa"}
AWS_REGION=${2:-"eu-north-1"}
DRY_RUN=${3:-"false"}

echo "🔧 Terraform State Fix Tool"
echo "Cluster: $CLUSTER_NAME | Region: $AWS_REGION | Dry Run: $DRY_RUN"
echo "=========================================="
echo ""

# Check if we're in the terraform directory
if [[ ! -f "provider.tf" ]]; then
    echo "❌ Error: Must be run from rosa/terraform directory"
    echo "   Run: cd rosa/terraform && ./fix-state-before-next-run.sh"
    exit 1
fi

# Check if Terraform is initialized
if [[ ! -d ".terraform" ]]; then
    echo "❌ Error: Terraform not initialized"
    echo "   Run: terraform init first"
    exit 1
fi

echo "📊 Current Terraform state resources:"
CURRENT_RESOURCES=$(terraform state list 2>/dev/null || echo "")
if [[ -z "$CURRENT_RESOURCES" ]]; then
    echo "   (No resources in state - nothing to fix)"
    exit 0
fi
echo "$CURRENT_RESOURCES"
echo ""

# Check if ROSA cluster actually exists
echo "🔍 Checking if ROSA cluster exists in AWS/OCM..."
ROSA_EXISTS="false"
if rosa describe cluster -c "$CLUSTER_NAME" &>/dev/null; then
    ROSA_EXISTS="true"
    echo "   ✅ ROSA cluster '$CLUSTER_NAME' exists in OCM"
else
    echo "   ❌ ROSA cluster '$CLUSTER_NAME' NOT found in OCM"
fi

# Check for ROSA resources in state
ROSA_STATE_RESOURCES=$(terraform state list 2>/dev/null | grep -E "^module\.rosa-hcp" || echo "")

if [[ -z "$ROSA_STATE_RESOURCES" ]]; then
    echo ""
    echo "✅ No ROSA resources in Terraform state - nothing to fix"
    exit 0
fi

echo ""
echo "📋 ROSA resources in Terraform state:"
echo "$ROSA_STATE_RESOURCES"
echo ""

if [[ "$ROSA_EXISTS" == "true" ]]; then
    echo "⚠️  ROSA cluster exists in AWS! Not removing from state."
    echo "   If you want to remove it, first delete the cluster:"
    echo "   rosa delete cluster -c $CLUSTER_NAME --yes"
    exit 0
fi

echo "🔄 ROSA cluster doesn't exist but is in state - this causes the error:"
echo "   'Failed getting cluster default ingress... Cluster not found'"
echo ""

# Remove stale ROSA resources from state
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 DRY RUN - Would remove these resources from state:"
    echo "$ROSA_STATE_RESOURCES" | while read -r resource; do
        echo "   terraform state rm '$resource'"
    done
else
    echo "🗑️  Removing stale ROSA resources from Terraform state..."
    
    # Remove in reverse order to handle dependencies
    # First try to remove the entire module at once
    if terraform state rm 'module.rosa-hcp' 2>/dev/null; then
        echo "   ✅ Removed module.rosa-hcp (entire module)"
    else
        # If module removal fails, remove resources individually
        echo "   Removing resources individually..."
        echo "$ROSA_STATE_RESOURCES" | sort -r | while read -r resource; do
            if terraform state rm "$resource" 2>/dev/null; then
                echo "   ✅ Removed: $resource"
            else
                echo "   ⚠️  Could not remove: $resource (may already be gone)"
            fi
        done
    fi
fi

echo ""
echo "📊 Remaining Terraform state resources:"
terraform state list 2>/dev/null || echo "   (No resources remaining)"

echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 DRY RUN complete - no changes made"
    echo "   Run without 'true' to actually fix: ./fix-state-before-next-run.sh $CLUSTER_NAME $AWS_REGION"
else
    echo "✅ State fix complete!"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Verify: terraform plan -var='redhat_ocm_token=YOUR_TOKEN'"
    echo "   2. Should show: 'Plan: X to add, 0 to change, 0 to destroy'"
    echo "   3. Re-run your pipeline or: terraform apply"
fi

