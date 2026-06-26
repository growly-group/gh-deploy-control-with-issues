#!/usr/bin/env bash
# HTTP health check for deployed services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/audit.sh
source "${SCRIPT_DIR}/lib/audit.sh"

SERVICE="${1:?service name required}"
CONFIG_FILE="${CONFIG_FILE:-deploy.config.yaml}"

write_failure_detail() {
  local detail="$1"
  {
    echo "failure_detail<<EOF"
    echo "$detail"
    echo "EOF"
  } >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
}

http_status_accepted() {
  local http_code="$1"
  local accept_json="$2"

  if [[ "$accept_json" != "[]" && "$accept_json" != "null" && -n "$accept_json" ]]; then
    echo "$accept_json" | jq -e --argjson code "$http_code" \
      'any(. == $code or (.|tostring) == ($code|tostring))' >/dev/null
    return $?
  fi

  [[ "$http_code" =~ ^2 ]]
}

run_healthcheck() {
  if [[ "$(cfg_healthcheck_enabled)" != "true" ]]; then
    echo "status=skipped" >> "$GITHUB_OUTPUT"
    audit_healthcheck "$SERVICE" "SKIPPED" "healthcheck disabled"
    return 0
  fi

  local url
  url="$(cfg_service_healthcheck_url "$SERVICE")"

  if [[ -z "$url" || "$url" == "null" ]]; then
    echo "::warning::No healthcheck.url for ${SERVICE}; skipping"
    echo "status=skipped" >> "$GITHUB_OUTPUT"
    audit_healthcheck "$SERVICE" "SKIPPED" "no url configured"
    return 0
  fi

  local timeout retries interval follow_redirects accept_json
  timeout="$(cfg_healthcheck_timeout)"
  retries="$(cfg_healthcheck_retries)"
  interval="$(cfg_healthcheck_interval)"
  follow_redirects="$(cfg_service_healthcheck_follow_redirects "$SERVICE")"
  accept_json="$(cfg_service_healthcheck_accept_status_json "$SERVICE")"

  local attempt=0 http_code curl_err last_detail=""
  local curl_args=(-o /dev/null -sS -w "%{http_code}" --max-time "$timeout")
  if [[ "$follow_redirects" == "true" ]]; then
    curl_args+=(-L)
  fi

  while [[ $attempt -lt $retries ]]; do
    attempt=$((attempt + 1))
    http_code=0
    curl_err=""
    if http_code=$(curl "${curl_args[@]}" "$url" 2>/tmp/curl.err); then
      if http_status_accepted "$http_code" "$accept_json"; then
        echo "status=success" >> "$GITHUB_OUTPUT"
        audit_healthcheck "$SERVICE" "OK" "${attempt}/${retries}"
        return 0
      fi
      last_detail="GET ${url} → HTTP ${http_code} (attempt ${attempt}/${retries})"
    else
      curl_err="$(tr '\n' ' ' </tmp/curl.err | head -c 500)"
      last_detail="GET ${url} → error: ${curl_err:-connection failed} (attempt ${attempt}/${retries})"
    fi
    echo "$last_detail"
    sleep "$interval"
  done

  local final_detail="GET ${url} → failed after ${retries} attempts. Last: ${last_detail}"
  echo "status=failure" >> "$GITHUB_OUTPUT"
  write_failure_detail "$final_detail"
  audit_healthcheck "$SERVICE" "FAILED" "${retries}/${retries}"
  audit_failure_detected "$SERVICE" "health check failed" "$final_detail"
  return 1
}

run_healthcheck
