#!/usr/bin/env bash
# Example custom deploy script — copy to .github/deploy-scripts/ in your repository.
set -euo pipefail

echo "Example worker deploy: SERVICE=${SERVICE} IMAGE=${IMAGE}"

if [[ "${ROLLBACK_MODE:-false}" == "true" ]]; then
  echo "Rolling back worker to ${IMAGE}"
  exit 0
fi

echo "Deploy worker with image ${IMAGE}"
exit 0
