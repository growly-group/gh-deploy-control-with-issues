#!/usr/bin/env bash
# Example custom deploy script for the "script" strategy.
# Environment variables provided by the platform:
#   SERVICE       - service name from deploy.config.yaml
#   IMAGE         - container image to deploy (or rollback target when ROLLBACK_MODE=true)
#   ROLLBACK_MODE - "true" when executing a rollback
#   PREVIOUS_REF  - previous image reference (when available)
#
# Optional: record refs for rollback/changelog (read after script exits successfully):
#   echo "$PREVIOUS_REF" > "/tmp/deploy-previous-ref-${SERVICE}"
#   echo "$DEPLOYED_REF" > "/tmp/deploy-deployed-ref-${SERVICE}"
# If absent, deployed_ref falls back to IMAGE.
set -euo pipefail

echo "Deploying service=${SERVICE} image=${IMAGE} rollback=${ROLLBACK_MODE:-false}"

if [[ "${ROLLBACK_MODE:-false}" == "true" ]]; then
  echo "Rollback mode: restoring ${IMAGE}"
  exit 0
fi

echo "Pull and restart ${IMAGE} for ${SERVICE}"
# Replace with your deployment logic (kubectl, docker, helm, etc.)
exit 0
