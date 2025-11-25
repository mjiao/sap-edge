#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

# delete-rosa-roles.sh
# Script to safely delete ROSA IAM roles and their policies

set -e

CLUSTER_NAME=${1:-"sap-eic-rosa"}

echo "🗑️  Deleting ROSA IAM roles for cluster: $CLUSTER_NAME"
echo "⚠️  This will delete the roles and allow Terraform to recreate them."
echo ""

# Function to delete role with all its policies
delete_role_with_policies() {
    local role_name="$1"

    echo "🔍 Processing role: $role_name"

    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        echo "   Found role, detaching policies..."

        # Detach managed policies
        aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | while read policy_arn; do
            if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                echo "   Detaching managed policy: $policy_arn"
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || echo "   Failed to detach $policy_arn"
            fi
        done

        # Delete inline policies
        aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[*]' --output text 2>/dev/null | while read policy_name; do
            if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
                echo "   Deleting inline policy: $policy_name"
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" || echo "   Failed to delete $policy_name"
            fi
        done

        # Delete instance profiles if any
        aws iam list-instance-profiles-for-role --role-name "$role_name" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null | while read profile_name; do
            if [[ -n "$profile_name" && "$profile_name" != "None" ]]; then
                echo "   Removing from instance profile: $profile_name"
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile_name" --role-name "$role_name" || echo "   Failed to remove from $profile_name"
            fi
        done

        # Finally delete the role
        echo "   Deleting role: $role_name"
        aws iam delete-role --role-name "$role_name"
        echo "   ✅ Deleted: $role_name"
    else
        echo "   ℹ️  Role not found: $role_name"
    fi
    echo ""
}

# Delete account roles
echo "🗑️  Deleting ROSA account roles..."
delete_role_with_policies "$CLUSTER_NAME-HCP-ROSA-Installer-Role"
delete_role_with_policies "$CLUSTER_NAME-HCP-ROSA-Support-Role"
delete_role_with_policies "$CLUSTER_NAME-HCP-ROSA-Worker-Role"

# Delete operator roles (from the error messages)
echo "🗑️  Deleting ROSA operator roles..."
delete_role_with_policies "$CLUSTER_NAME-openshift-image-registry-installer-cloud-credential"
delete_role_with_policies "$CLUSTER_NAME-kube-system-capa-controller-manager"
delete_role_with_policies "$CLUSTER_NAME-kube-system-kms-provider"
delete_role_with_policies "$CLUSTER_NAME-openshift-cluster-csi-drivers-ebs-cloud-credentials"
delete_role_with_policies "$CLUSTER_NAME-kube-system-control-plane-operator"
delete_role_with_policies "$CLUSTER_NAME-openshift-ingress-operator-cloud-credentials"
delete_role_with_policies "$CLUSTER_NAME-openshift-cloud-network-config-controller-cloud-cre"
delete_role_with_policies "$CLUSTER_NAME-kube-system-kube-controller-manager"

# Delete any other operator roles that might exist
echo "🔍 Finding any additional ROSA operator roles..."
aws iam list-roles --query "Roles[?contains(RoleName, '$CLUSTER_NAME-')].RoleName" --output text 2>/dev/null | tr '\t' '\n' | while read role_name; do
    if [[ -n "$role_name" && "$role_name" != "None" ]]; then
        # Skip if we already processed it above
        if [[ "$role_name" != "$CLUSTER_NAME-HCP-ROSA-"* ]]; then
            echo "   Found additional role: $role_name"
            delete_role_with_policies "$role_name"
        fi
    fi
done

echo "🎉 ROSA role cleanup completed!"
echo ""
echo "✅ Now you can re-run your Terraform pipeline and it should create all roles successfully."