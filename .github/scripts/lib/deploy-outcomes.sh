#!/usr/bin/env bash
# Per-service deploy and health outcome helpers.
set -euo pipefail

read_outcome_file() {
  local dir="$1"
  local service="$2"
  local prefix="${3:-}"
  local file

  if [[ -n "$prefix" ]]; then
    file="${dir}/${prefix}-${service}.txt"
    if [[ -f "$file" ]]; then
      tr -d '[:space:]' < "$file"
      return 0
    fi
  fi

  file="${dir}/${service}.txt"
  if [[ -f "$file" ]]; then
    tr -d '[:space:]' < "$file"
    return 0
  fi

  echo "unknown"
}

deploy_outcome_for_service() {
  local dir="$1"
  local service="$2"
  local outcome

  outcome="$(read_outcome_file "$dir" "$service" "deploy-outcome")"
  if [[ "$outcome" == "unknown" ]]; then
    outcome="$(read_outcome_file "$dir" "$service")"
  fi
  echo "$outcome"
}

health_outcome_for_service() {
  local deploy_dir="$1"
  local health_dir="$2"
  local service="$3"
  local deploy_outcome health_outcome

  deploy_outcome="$(deploy_outcome_for_service "$deploy_dir" "$service")"
  if [[ "$deploy_outcome" != "success" ]]; then
    echo "skipped"
    return 0
  fi

  health_outcome="$(read_outcome_file "$health_dir" "$service" "health-outcome")"
  if [[ "$health_outcome" == "unknown" ]]; then
    health_outcome="$(read_outcome_file "$health_dir" "$service")"
  fi
  echo "$health_outcome"
}

service_needs_rollback() {
  local deploy_dir="$1"
  local health_dir="$2"
  local service="$3"
  local deploy_outcome health_outcome

  deploy_outcome="$(deploy_outcome_for_service "$deploy_dir" "$service")"
  if [[ "$deploy_outcome" != "success" ]]; then
    return 0
  fi

  health_outcome="$(health_outcome_for_service "$deploy_dir" "$health_dir" "$service")"
  if [[ "$health_outcome" == "failure" ]]; then
    return 0
  fi

  return 1
}

summarize_deploy_outcomes() {
  local outcomes_dir="$1"
  local services_csv="$2"
  local succeeded=() failed=() outcome service

  IFS=',' read -ra services <<< "$services_csv"
  for service in "${services[@]}"; do
    [[ -z "$service" ]] && continue
    outcome="$(deploy_outcome_for_service "$outcomes_dir" "$service")"
    if [[ "$outcome" == "success" ]]; then
      succeeded+=("$service")
    else
      failed+=("$service")
    fi
  done

  {
    echo "succeeded_services=$(IFS=,; echo "${succeeded[*]}")"
    echo "failed_services=$(IFS=,; echo "${failed[*]}")"
    if [[ ${#failed[@]} -eq 0 && ${#succeeded[@]} -gt 0 ]]; then
      echo "all_succeeded=true"
      echo "any_failed=false"
    elif [[ ${#failed[@]} -gt 0 ]]; then
      echo "all_succeeded=false"
      echo "any_failed=true"
    else
      echo "all_succeeded=false"
      echo "any_failed=true"
    fi
  } >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
}

summarize_pipeline_outcomes() {
  local deploy_dir="$1"
  local health_dir="$2"
  local services_csv="$3"
  local healthcheck_enabled="${4:-true}"
  local service deploy_outcome health_outcome

  deploy_succeeded=""
  deploy_failed=""
  health_succeeded=""
  health_failed=""
  health_skipped=""

  IFS=',' read -ra services <<< "$services_csv"
  for service in "${services[@]}"; do
    [[ -z "$service" ]] && continue
    deploy_outcome="$(deploy_outcome_for_service "$deploy_dir" "$service")"
    if [[ "$deploy_outcome" == "success" ]]; then
      deploy_succeeded="${deploy_succeeded:+$deploy_succeeded,}$service"
      if [[ "$healthcheck_enabled" != "true" ]]; then
        health_skipped="${health_skipped:+$health_skipped,}$service"
      else
        health_outcome="$(health_outcome_for_service "$deploy_dir" "$health_dir" "$service")"
        case "$health_outcome" in
          success)
            health_succeeded="${health_succeeded:+$health_succeeded,}$service"
            ;;
          failure)
            health_failed="${health_failed:+$health_failed,}$service"
            ;;
          *)
            health_skipped="${health_skipped:+$health_skipped,}$service"
            ;;
        esac
      fi
    else
      deploy_failed="${deploy_failed:+$deploy_failed,}$service"
      health_skipped="${health_skipped:+$health_skipped,}$service"
    fi
  done

  export deploy_succeeded deploy_failed health_succeeded health_failed health_skipped
}

rollback_outcome_for_service() {
  local dir="$1"
  local service="$2"
  read_outcome_file "$dir" "$service" "rollback-result"
}
