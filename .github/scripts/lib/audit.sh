#!/usr/bin/env bash
# Audit logging — posts deployment events to the issue.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/gh-issue.sh"

audit_started() {
  local services="$1"
  issue_comment "🟡 **Deploy started** — services: \`${services}\`"
}

audit_waiting_approval() {
  local users="$1"
  issue_comment "⏳ **Waiting for approval** — react with 🚀 to approve.

Authorized users: ${users}

- 🚀 Approve deploy
- 👎 Reject deploy"
}

audit_approved() {
  local user="$1"
  issue_comment "✅ **Deploy approved** by @${user}"
}

audit_rejected() {
  local user="$1"
  issue_comment "❌ **Deploy rejected** by @${user} — deploy cancelled."
}

audit_deploying() {
  local service="$1"
  local image="$2"
  issue_comment "🔧 **Deploying** \`${service}\` (\`${image}\`)"
}

audit_healthcheck() {
  local service="$1"
  local status="$2"
  local detail="$3"
  issue_comment "🏥 **Health check** \`${service}\`: ${status} (${detail})"
}

audit_rollback() {
  local service="$1"
  local ref="$2"
  local reason="$3"
  local actor="${4:-automatic}"
  issue_comment "⏪ **Rollback completed** \`${service}\` → \`${ref}\` — ${reason} (by ${actor})"
}

audit_failure_detected() {
  local service="$1"
  local reason="$2"
  local detail="${3:-}"
  local body="⚠️ **Failure detected** in \`${service}\` — ${reason}"
  if [[ -n "$detail" ]]; then
    body+=$'\n\n'"${detail}"
  fi
  issue_comment "$body"
}

audit_rollback_triggered() {
  local reason="$1"
  local services="$2"
  local mentions="$3"
  local failure_summary="${4:-}"
  local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

  local body="🚨 **Deploy failed — automatic rollback started**

**Reason:** ${reason}
**Affected services:** \`${services}\`
**Action:** restoring previous version"

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$failure_summary" ]]; then
    body+=$'\n\n'"${failure_summary}"
  fi

  body+=$'\n\n'"**Full logs:** ${run_url}"
  issue_comment "$body"
}

audit_rollback_started() {
  local service="$1"
  local previous_ref="$2"
  local failed_ref="$3"
  issue_comment "🔄 **Starting rollback** \`${service}\` — restoring \`${previous_ref}\` (failed at \`${failed_ref}\`)"
}

audit_rollback_skipped() {
  local service="$1"
  local reason="$2"
  issue_comment "⏭️ **Rollback skipped** for \`${service}\` — ${reason}"
}

audit_rollback_failed() {
  local service="$1"
  local ref="$2"
  local error="$3"
  local actor="${4:-automatic}"
  issue_comment "❌ **Rollback failed** for \`${service}\` → \`${ref}\` (by ${actor})

\`\`\`
${error}
\`\`\`"
}

audit_rollback_summary() {
  local outcome="$1"
  local mentions="$2"
  local details="${3:-}"
  local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

  local body
  case "$outcome" in
    restored)
      body="✅ **Deploy failed, environment restored**

The deploy did not complete successfully, but automatic rollback restored the previous version."
      ;;
    failed)
      body="💥 **Deploy and rollback failed**

The deploy failed and automatic rollback was also unsuccessful. **Manual intervention required.**"
      ;;
    partial)
      body="⚠️ **Deploy failed — partial rollback**

Some services were restored; others failed or had no previous version recorded."
      ;;
    *)
      body="💥 **Deploy failed**"
      ;;
  esac

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$details" ]]; then
    body+=$'\n\n'"${details}"
  fi

  body+=$'\n\n'"**Full logs:** ${run_url}"
  issue_comment "$body"
}

audit_success() {
  issue_comment "✅ **Deploy completed successfully**"
}

audit_success_notify() {
  local services="$1"
  local mentions="$2"
  local changelog_url="${3:-}"
  local changelog_summary="${4:-}"
  local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

  local body="🎉 **Deploy completed successfully**

**Deployed services:** \`${services}\`"

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$changelog_url" ]]; then
    body+=$'\n\n'"**Changelog (diff between deploys):** ${changelog_url}"
  fi

  if [[ -n "$changelog_summary" ]]; then
    body+=$'\n\n'"<details>"
    body+=$'\n'"<summary>Summary of changes</summary>"
    body+=$'\n'""
    body+=$'\n'"${changelog_summary}"
    body+=$'\n'""
    body+=$'\n'"</details>"
  fi

  body+=$'\n\n'"**Deploy logs:** ${run_url}"
  issue_comment "$body"
}

audit_failure() {
  local reason="$1"
  issue_comment "💥 **Deploy failed** — ${reason}

View logs: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
}

audit_no_targets() {
  issue_comment "⚠️ **No deploy targets identified** — select services in the issue form or add labels matching \`deploy.config.yaml\` service keys."
}

audit_invalid_type() {
  local expected="$1"
  local actual="$2"
  issue_comment "⚠️ **Invalid issue type** — expected: \`${expected}\`, actual: \`${actual:-none}\`."
}

audit_state_recorded() {
  local service="$1"
  local previous_ref="$2"
  issue_comment "📋 **State recorded** \`${service}\` — previous version: \`${previous_ref}\`"
}
