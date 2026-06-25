#!/usr/bin/env bash
# GitHub CLI wrappers for issue operations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/config.sh"

REPO="${GITHUB_REPOSITORY:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"

gh_require() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error::GitHub CLI (gh) is required but not installed." >&2
    exit 1
  fi
}

issue_view_json() {
  local number="${1:-$ISSUE_NUMBER}"
  gh issue view "$number" --json issueType,labels,state,title,author
}

issue_author() {
  local number="${1:-$ISSUE_NUMBER}"
  issue_view_json "$number" | jq -r '.author.login // empty'
}

issue_mentions() {
  local number="${1:-$ISSUE_NUMBER}"
  local author mention="" user
  author="$(issue_author "$number")"
  if [[ -n "$author" ]]; then
    mention="@${author}"
  fi
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    if [[ "$user" != "$author" ]]; then
      mention="${mention} @${user}"
    fi
  done < <(cfg_approval_users)
  echo "$mention" | sed 's/^ //'
}

issue_type_name() {
  local number="${1:-$ISSUE_NUMBER}"
  issue_view_json "$number" | jq -r '.issueType.name // empty'
}

issue_label_names() {
  local number="${1:-$ISSUE_NUMBER}"
  issue_view_json "$number" | jq -r '.labels[].name'
}

issue_comment() {
  local body="$1"
  local number="${2:-$ISSUE_NUMBER}"
  gh issue comment "$number" --body "$body"
}

issue_close() {
  local number="${1:-$ISSUE_NUMBER}"
  gh issue close "$number"
}

issue_add_label() {
  local label="$1"
  local number="${2:-$ISSUE_NUMBER}"
  gh issue edit "$number" --add-label "$label"
}

issue_reactions() {
  local number="${1:-$ISSUE_NUMBER}"
  gh api "repos/${REPO}/issues/${number}/reactions" --paginate
}

reaction_users_by_content() {
  local content="$1"
  local number="${2:-$ISSUE_NUMBER}"
  issue_reactions "$number" | jq -r --arg c "$content" '.[] | select(.content == $c) | .user.login'
}
