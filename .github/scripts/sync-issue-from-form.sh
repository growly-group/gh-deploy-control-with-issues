#!/usr/bin/env bash
# Apply deploy labels from issue form checkboxes (GitHub forms do not map checkboxes to labels).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/lib/gh-issue.sh"

gh_require

if [[ -z "${ISSUE_NUMBER:-}" ]]; then
  echo "::error::ISSUE_NUMBER is required." >&2
  exit 1
fi

issue_sync_labels_from_form "$ISSUE_NUMBER"
