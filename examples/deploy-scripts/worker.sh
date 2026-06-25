#!/usr/bin/env bash
# Example custom deploy script — copy to .github/deploy-scripts/ in your repository.
#
# Environment variables provided by the deploy action:
#   SERVICE        - service name from deploy.config.yaml
#   IMAGE          - image reference to deploy
#   ROLLBACK_MODE  - "true" when rolling back (deploy previous ref via IMAGE)
#   PREVIOUS_REF   - ref recorded before deploy (for rollback context)
#
# Optional: record refs for rollback/changelog (written after script exits successfully):
#   echo "$PREVIOUS_REF" > "/tmp/deploy-previous-ref-${SERVICE}"
#   echo "$DEPLOYED_REF" > "/tmp/deploy-deployed-ref-${SERVICE}"
# If absent, deployed_ref falls back to IMAGE.
set -euo pipefail

echo "Example worker deploy: SERVICE=${SERVICE} IMAGE=${IMAGE}"

if [[ "${ROLLBACK_MODE:-false}" == "true" ]]; then
  echo "Rolling back worker to ${IMAGE}"
  exit 0
fi

echo "Deploy worker with image ${IMAGE}"
exit 0
