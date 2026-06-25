#!/usr/bin/env bash
# Build dynamic deployment matrix from issue labels and deploy.config.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/gh-issue.sh"
# shellcheck source=lib/audit.sh
source "${SCRIPT_DIR}/audit.sh"

validate_deploy_issue() {
  local expected_type fallback_label actual_type labels
  expected_type="$(cfg_issue_type)"
  fallback_label="$(cfg_fallback_trigger_label)"

  actual_type="$(issue_type_name)"
  labels="$(issue_label_names | tr '\n' ' ')"

  local trigger_ok=false
  if [[ "$actual_type" == "$expected_type" ]]; then
    trigger_ok=true
  elif echo " $labels " | grep -q " ${fallback_label} "; then
    trigger_ok=true
  fi

  if [[ "$trigger_ok" != "true" ]]; then
    audit_invalid_type "$expected_type" "$actual_type"
    issue_comment "ℹ️ For user-owned repositories without Issue Types, add the \`${fallback_label}\` label to the issue."
    echo "valid=false" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
    echo "reason=invalid_issue_type" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  local services=()
  local service
  while IFS= read -r service; do
    [[ -n "$service" ]] && services+=("$service")
  done < <(issue_selected_services)

  if [[ ${#services[@]} -eq 0 ]]; then
    audit_no_targets
    echo "valid=false" >> "$GITHUB_OUTPUT"
    echo "reason=no_service_labels" >> "$GITHUB_OUTPUT"
    exit 0
  fi

  local services_csv
  services_csv="$(IFS=,; echo "${services[*]}")"

  audit_started "$services_csv"

  echo "valid=true" >> "$GITHUB_OUTPUT"
  echo "services=${services_csv}" >> "$GITHUB_OUTPUT"
  echo "approval_enabled=$(cfg_approval_enabled)" >> "$GITHUB_OUTPUT"
  echo "rollback_enabled=$(cfg_rollback_enabled)" >> "$GITHUB_OUTPUT"
  echo "rollback_automatic=$(cfg_rollback_automatic)" >> "$GITHUB_OUTPUT"
  echo "healthcheck_enabled=$(cfg_healthcheck_enabled)" >> "$GITHUB_OUTPUT"
  echo "notify_on_success=$(cfg_observability_notify_on_success)" >> "$GITHUB_OUTPUT"
  echo "changelog_enabled=$(cfg_changelog_enabled)" >> "$GITHUB_OUTPUT"
}

build_matrix_json() {
  local services_csv="$1"
  IFS=',' read -ra services <<< "$services_csv"

  local include_items=()
  local service strategy image config_json

  for service in "${services[@]}"; do
    strategy="$(cfg_service_field "$service" "strategy")"
    image="$(cfg_service_field "$service" "image")"
    config_json="$(cfg_json ".services.${service}.config // {}")"

    include_items+=("$(jq -nc \
      --arg service "$service" \
      --arg strategy "$strategy" \
      --arg image "$image" \
      --argjson config "$config_json" \
      '{service: $service, strategy: $strategy, image: $image, config: ($config | tostring)}')")
  done

  local matrix_json
  matrix_json="$(printf '%s\n' "${include_items[@]}" | jq -s '{include: .}')"
  echo "$matrix_json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  gh_require
  case "${1:-}" in
    validate)
      validate_deploy_issue
      ;;
    matrix)
      build_matrix_json "${2:?services csv required}"
      ;;
    *)
      echo "Usage: $0 {validate|matrix <services>}" >&2
      exit 1
      ;;
  esac
fi
