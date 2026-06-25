#!/usr/bin/env bash
# Poll issue reactions for approval, rejection, and manual rollback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/gh-issue.sh"

APPROVAL_TIMEOUT_SECONDS="${APPROVAL_TIMEOUT_SECONDS:-86400}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-30}"

find_authorized_reaction() {
  local content="$1"
  local user
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    if is_authorized_user "$user"; then
      echo "$user"
      return 0
    fi
  done < <(reaction_users_by_content "$content")
  return 1
}

wait_for_approval() {
  local deadline=$((SECONDS + APPROVAL_TIMEOUT_SECONDS))

  while [[ $SECONDS -lt $deadline ]]; do
    local rejecter
    if rejecter="$(find_authorized_reaction "-1" 2>/dev/null || true)" && [[ -n "$rejecter" ]]; then
      echo "rejected:${rejecter}"
      return 1
    fi

    local approver
    if approver="$(find_authorized_reaction "rocket" 2>/dev/null || true)" && [[ -n "$approver" ]]; then
      echo "approved:${approver}"
      return 0
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  echo "::error::Approval timeout after ${APPROVAL_TIMEOUT_SECONDS}s" >&2
  return 2
}

check_manual_rollback() {
  local user
  if user="$(find_authorized_reaction "eyes" 2>/dev/null || true)" && [[ -n "$user" ]]; then
    echo "$user"
    return 0
  fi
  return 1
}
