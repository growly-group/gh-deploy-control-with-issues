#!/usr/bin/env bash
# Shared configuration helpers — reads deploy.config.yaml via yq.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-deploy.config.yaml}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "::error::Configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi

cfg() {
  local query="$1"
  yq -r "$query" "$CONFIG_FILE"
}

cfg_json() {
  local query="$1"
  yq -o=json -I=0 "$query" "$CONFIG_FILE"
}

cfg_issue_type() {
  cfg '.deployment.issue_type // "Deploy"'
}

cfg_fallback_trigger_label() {
  local fallback
  fallback="$(cfg '.deployment.fallback_trigger_label // ""')"
  if [[ -n "$fallback" && "$fallback" != "null" ]]; then
    echo "$fallback"
    return
  fi
  cfg_issue_type | tr '[:upper:]' '[:lower:]'
}

cfg_approval_enabled() {
  cfg '.deployment.approval.enabled // false'
}

cfg_approval_users() {
  cfg '.deployment.approval.users // [] | .[]'
}

cfg_rollback_enabled() {
  cfg '.deployment.rollback.enabled // false'
}

cfg_rollback_automatic() {
  cfg '.deployment.rollback.automatic // false'
}

cfg_healthcheck_enabled() {
  cfg '.deployment.healthcheck.enabled // true'
}

cfg_healthcheck_timeout() {
  cfg '.deployment.healthcheck.timeout // 300'
}

cfg_healthcheck_retries() {
  cfg '.deployment.healthcheck.retries // 10'
}

cfg_healthcheck_interval() {
  cfg '.deployment.healthcheck.interval // 15'
}

cfg_healthcheck_endpoint() {
  cfg '.deployment.healthcheck.endpoint // "/health"'
}

cfg_observability_include_failed_logs() {
  cfg '.deployment.observability.include_failed_logs // true'
}

cfg_observability_max_log_lines() {
  cfg '.deployment.observability.max_log_lines // 40'
}

cfg_observability_max_log_chars() {
  cfg '.deployment.observability.max_log_chars // 3500'
}

cfg_observability_notify_on_success() {
  cfg '.deployment.observability.notify_on_success // true'
}

cfg_changelog_enabled() {
  cfg '.deployment.observability.changelog.enabled // true'
}

cfg_changelog_max_commits() {
  cfg '.deployment.observability.changelog.max_commits // 20'
}

cfg_changelog_state_variable() {
  cfg '.deployment.observability.changelog.state_variable // "DEPLOY_LAST_GIT_SHA"'
}

cfg_service_names() {
  cfg '.services | keys | .[]'
}

cfg_service_field() {
  local service="$1"
  local field="$2"
  cfg ".services.${service}.${field}"
}

cfg_service_healthcheck_url() {
  local service="$1"
  local url
  url="$(cfg ".services.${service}.healthcheck.url // \"\"")"
  if [[ -n "$url" && "$url" != "null" ]]; then
    echo "$url"
    return
  fi
  echo ""
}

cfg_service_healthcheck_endpoint() {
  local service="$1"
  cfg ".services.${service}.healthcheck.endpoint // \"\""
}

cfg_service_deploy_option_ids() {
  local service="$1"
  cfg ".services.${service}.options.deploy_options // [] | .[].id"
}

cfg_deploy_option_label() {
  local service="$1"
  local option_id="$2"
  cfg ".services.${service}.options.deploy_options[] | select(.id == \"${option_id}\") | .label // .id"
}

cfg_deploy_option_checkbox() {
  local service="$1"
  local option_id="$2"
  cfg ".services.${service}.options.deploy_options[] | select(.id == \"${option_id}\") | .checkbox // .label // .id"
}

cfg_deploy_option_description() {
  local service="$1"
  local option_id="$2"
  cfg ".services.${service}.options.deploy_options[] | select(.id == \"${option_id}\") | .description // \"\""
}

cfg_service_has_deploy_options() {
  local service="$1"
  local id
  id="$(cfg_service_deploy_option_ids "$service" | head -1)"
  [[ -n "$id" && "$id" != "null" ]]
}

cfg_issue_template_intro() {
  local intro
  intro="$(cfg '.deployment.issue_template.intro // ""')"
  if [[ -z "$intro" || "$intro" == "null" ]]; then
    printf '%s\n' \
      "Select the services to deploy. Service labels are applied automatically when the issue is opened." \
      "After opening, an authorized user can approve with 🚀." \
      "Reject: 👎 · Manual rollback: 👀"
  else
    echo "$intro"
  fi
}

cfg_issue_template_services_description() {
  cfg '.deployment.issue_template.services_description // "Select all services that should be deployed."'
}

cfg_issue_template_reason_placeholder() {
  cfg '.deployment.issue_template.reason_placeholder // "Deploy v1.2.0 after merging PR #42"'
}

cfg_issue_template_notes_description() {
  cfg '.deployment.issue_template.notes_description // "Expected rollback, dependencies, maintenance window..."'
}

is_authorized_user() {
  local user="$1"
  local allowed
  while IFS= read -r allowed; do
    [[ -z "$allowed" ]] && continue
    if [[ "$allowed" == "$user" ]]; then
      return 0
    fi
  done < <(cfg_approval_users)
  return 1
}
