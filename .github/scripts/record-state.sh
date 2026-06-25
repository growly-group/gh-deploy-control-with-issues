#!/usr/bin/env bash
# Record pre-deploy state for rollback.
set -euo pipefail

SERVICE="${1:?service name required}"
STATE_DIR="${STATE_DIR:-/tmp/deploy-state}"
mkdir -p "$STATE_DIR"

PREVIOUS_REF="${PREVIOUS_REF:-unknown}"
DEPLOYED_REF="${DEPLOYED_REF:-}"

echo "$PREVIOUS_REF" > "${STATE_DIR}/${SERVICE}.previous"
if [[ -n "$DEPLOYED_REF" ]]; then
  echo "$DEPLOYED_REF" > "${STATE_DIR}/${SERVICE}.deployed"
fi

echo "previous_ref=${PREVIOUS_REF}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
echo "deployed_ref=${DEPLOYED_REF}" >> "$GITHUB_OUTPUT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/audit.sh
source "${SCRIPT_DIR}/lib/audit.sh"
audit_state_recorded "$SERVICE" "$PREVIOUS_REF"
