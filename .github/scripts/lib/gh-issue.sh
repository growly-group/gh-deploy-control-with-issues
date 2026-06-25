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

issue_body() {
  local number="${1:-$ISSUE_NUMBER}"
  gh issue view "$number" --json body -q .body 2>/dev/null || true
}

issue_checkbox_checked() {
  local option="$1"
  local body="${2:-}"
  [[ -n "$body" ]] || return 1
  echo "$body" | grep -qF -- "- [x] ${option}"
}

issue_selected_services() {
  local number="${1:-$ISSUE_NUMBER}"
  local labels body service
  labels="$(issue_label_names "$number" | tr '\n' ' ')"
  body="$(issue_body "$number")"

  for service in $(cfg_service_names); do
    if echo " $labels " | grep -q " ${service} "; then
      echo "$service"
    elif issue_checkbox_checked "$service" "$body"; then
      echo "$service"
    fi
  done
}

issue_sync_labels_from_form() {
  local number="${1:-$ISSUE_NUMBER}"
  local body labels_to_add=() existing service option_id checkbox label
  body="$(issue_body "$number")"
  [[ -n "$body" ]] || return 0

  mapfile -t existing < <(issue_label_names "$number")

  label_present() {
    local name="$1"
    local lbl
    for lbl in "${existing[@]}"; do
      [[ "$lbl" == "$name" ]] && return 0
    done
    return 1
  }

  for service in $(cfg_service_names); do
    if issue_checkbox_checked "$service" "$body" && ! label_present "$service"; then
      labels_to_add+=("$service")
    fi
  done

  for service in $(cfg_service_names); do
    while IFS= read -r option_id; do
      [[ -z "$option_id" ]] && continue
      checkbox="$(cfg_deploy_option_checkbox "$service" "$option_id")"
      label="$(cfg_deploy_option_label "$service" "$option_id")"
      if issue_checkbox_checked "$checkbox" "$body" && ! label_present "$label"; then
        labels_to_add+=("$label")
      fi
    done < <(cfg_service_deploy_option_ids "$service")
  done

  local fallback
  fallback="$(cfg_fallback_trigger_label)"
  if [[ ${#labels_to_add[@]} -gt 0 || "$(issue_type_name "$number")" == "$(cfg_issue_type)" ]]; then
    if ! label_present "$fallback"; then
      labels_to_add+=("$fallback")
    fi
  fi

  if [[ ${#labels_to_add[@]} -eq 0 ]]; then
    return 0
  fi

  local args=()
  local lbl
  for lbl in "${labels_to_add[@]}"; do
    ensure_issue_label "$lbl" "$(issue_label_description "$lbl")"
    args+=(--add-label "$lbl")
  done
  gh issue edit "$number" "${args[@]}"
}

ensure_issue_label() {
  local name="$1"
  local description="$2"
  if gh label list --json name --jq '.[].name' | grep -qx "$name"; then
    return 0
  fi
  gh label create "$name" --description "$description"
}

issue_label_description() {
  local name="$1"
  local service option_id label fallback

  fallback="$(cfg_fallback_trigger_label)"
  if [[ "$name" == "$fallback" ]]; then
    echo "Triggers deployment workflow (fallback when Issue Types are unavailable)"
    return
  fi

  for service in $(cfg_service_names); do
    while IFS= read -r option_id; do
      [[ -z "$option_id" ]] && continue
      label="$(cfg_deploy_option_label "$service" "$option_id")"
      if [[ "$name" == "$label" ]]; then
        echo "Deploy option (${service}): ${option_id}"
        return
      fi
    done < <(cfg_service_deploy_option_ids "$service")
  done

  for service in $(cfg_service_names); do
    if [[ "$name" == "$service" ]]; then
      echo "Deploy target: ${service}"
      return
    fi
  done

  echo "Managed by deploy workflow"
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
