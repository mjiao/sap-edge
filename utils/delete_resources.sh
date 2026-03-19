#!/bin/bash

# SPDX-FileCopyrightText: 2025 SAP edge team
#
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

REMOVE_FINALIZERS_PATCH='[{"op": "replace", "path": "/metadata/finalizers", "value": []}]'
WAIT_TIMEOUT=60

# Default projects to clean up
DEFAULT_PROJECTS=(
  edge-icell
  edge-icell-ela
  edge-icell-secrets
  edge-icell-services
  edgelm
)

# Usage: ./delete_resources.sh [project_name ...]
# If no arguments are given, the default project list is used.
if [[ $# -gt 0 ]]; then
  PROJECTS=("$@")
else
  PROJECTS=("${DEFAULT_PROJECTS[@]}")
fi

delete_project() {
  local PROJECT=$1

  if ! oc get project "$PROJECT" &>/dev/null; then
    echo "Project '$PROJECT' not found; nothing to do."
    return 0
  fi

  # Step 1: Try normal deletion first
  echo "Deleting project '$PROJECT'..."
  oc delete project "$PROJECT" --wait=false 2>/dev/null || true

  # Wait for the project to disappear
  echo "Waiting up to ${WAIT_TIMEOUT}s for project to be deleted..."
  if oc wait project/"$PROJECT" --for=delete --timeout="${WAIT_TIMEOUT}s" 2>/dev/null; then
    echo "Project '$PROJECT' deleted successfully."
    return 0
  fi

  # Step 2: Project is stuck in Terminating — remove finalizers from all resources
  echo "Project '$PROJECT' is stuck in Terminating. Removing finalizers from remaining resources..."

  oc api-resources --verbs=list,patch --namespaced -o name | while read -r TYPE; do
    oc get "$TYPE" -n "$PROJECT" -o name 2>/dev/null | while read -r RES; do
      echo "  Removing finalizers from $RES..."
      oc patch "$RES" -n "$PROJECT" --type json -p "$REMOVE_FINALIZERS_PATCH" 2>/dev/null || true
    done
  done

  # Step 3: Wait for namespace to terminate after finalizers are cleared
  echo "Waiting for project '$PROJECT' to terminate..."
  if oc wait project/"$PROJECT" --for=delete --timeout="${WAIT_TIMEOUT}s" 2>/dev/null; then
    echo "Project '$PROJECT' deleted successfully."
  else
    echo "Warning: Project '$PROJECT' is still not deleted. Manual intervention may be needed."
    return 1
  fi
}

FAILED=0
for PROJECT in "${PROJECTS[@]}"; do
  delete_project "$PROJECT" || FAILED=1
done

exit $FAILED
