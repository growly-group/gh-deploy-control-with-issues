#!/usr/bin/env bash
# Extract a truncated excerpt from failed workflow step logs via gh CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

collect_failure_logs() {
  if [[ "$(cfg_observability_include_failed_logs)" != "true" ]]; then
    return 0
  fi

  local max_lines max_chars run_id repo
  max_lines="$(cfg_observability_max_log_lines)"
  max_chars="$(cfg_observability_max_log_chars)"
  run_id="${GITHUB_RUN_ID:?GITHUB_RUN_ID required}"
  repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"

  gh run view "$run_id" --repo "$repo" --log-failed 2>/dev/null \
    | tail -n "$max_lines" \
    | head -c "$max_chars" \
    || true
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  collect_failure_logs
fi
