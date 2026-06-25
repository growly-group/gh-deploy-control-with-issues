#!/usr/bin/env bash
# Build markdown failure summary from per-service artifact files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=collect-failure-logs.sh
source "${SCRIPT_DIR}/collect-failure-logs.sh"

FAILURE_DIR="${1:-/tmp/failure-logs}"

build_failure_summary() {
  local summary="" file detail workflow_logs service base

  if [[ -d "$FAILURE_DIR" ]]; then
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      base="$(basename "$file" .txt)"
      [[ "$base" == rollback-result-* ]] && continue
      service="${base#failure-log-}"
      detail="$(cat "$file")"
      summary+=$'\n'"<details>"
      summary+=$'\n'"<summary>${service} — failure detail</summary>"
      summary+=$'\n'""
      summary+=$'\n'"${detail}"
      summary+=$'\n'""
      summary+=$'\n'"</details>"
    done < <(find "$FAILURE_DIR" -type f -name '*.txt' 2>/dev/null | sort)
  fi

  workflow_logs="$(collect_failure_logs)"
  if [[ -n "$workflow_logs" ]]; then
    summary+=$'\n'"<details>"
    summary+=$'\n'"<summary>Workflow log excerpt</summary>"
    summary+=$'\n'""
    summary+=$'\n'"\`\`\`"
    summary+=$'\n'"${workflow_logs}"
    summary+=$'\n'"\`\`\`"
    summary+=$'\n'"</details>"
  fi

  echo "$summary" | sed '/^$/d' | head -c 60000
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  build_failure_summary "${1:-/tmp/failure-logs}"
fi
