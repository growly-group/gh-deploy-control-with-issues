#!/usr/bin/env bash
# Audit logging — posts deployment events to the issue.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/gh-issue.sh"

audit_started() {
  local services="$1"
  issue_comment "🟡 **Deploy iniciado** — serviços: \`${services}\`"
}

audit_waiting_approval() {
  local users="$1"
  issue_comment "⏳ **Aguardando aprovação** — reaja com 🚀 para aprovar.

Usuários autorizados: ${users}

- 🚀 Aprovar deploy
- 👎 Reprovar deploy"
}

audit_approved() {
  local user="$1"
  issue_comment "✅ **Deploy aprovado** por @${user}"
}

audit_rejected() {
  local user="$1"
  issue_comment "❌ **Deploy reprovado** por @${user} — deploy cancelado."
}

audit_deploying() {
  local service="$1"
  local image="$2"
  issue_comment "🔧 **Implantando** \`${service}\` (\`${image}\`)"
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
  local actor="${4:-automático}"
  issue_comment "⏪ **Rollback concluído** \`${service}\` → \`${ref}\` — ${reason} (por ${actor})"
}

audit_failure_detected() {
  local service="$1"
  local reason="$2"
  local detail="${3:-}"
  local body="⚠️ **Falha detectada** em \`${service}\` — ${reason}"
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

  local body="🚨 **Deploy falhou — rollback automático iniciado**

**Motivo:** ${reason}
**Serviços afetados:** \`${services}\`
**Ação:** restaurando versão anterior"

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$failure_summary" ]]; then
    body+=$'\n\n'"${failure_summary}"
  fi

  body+=$'\n\n'"**Logs completos:** ${run_url}"
  issue_comment "$body"
}

audit_rollback_started() {
  local service="$1"
  local previous_ref="$2"
  local failed_ref="$3"
  issue_comment "🔄 **Iniciando rollback** \`${service}\` — restaurando \`${previous_ref}\` (falha em \`${failed_ref}\`)"
}

audit_rollback_skipped() {
  local service="$1"
  local reason="$2"
  issue_comment "⏭️ **Rollback ignorado** para \`${service}\` — ${reason}"
}

audit_rollback_failed() {
  local service="$1"
  local ref="$2"
  local error="$3"
  local actor="${4:-automático}"
  issue_comment "❌ **Rollback falhou** em \`${service}\` → \`${ref}\` (por ${actor})

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
      body="✅ **Deploy falhou, ambiente restaurado**

O deploy não foi concluído com sucesso, mas o rollback automático restaurou a versão anterior."
      ;;
    failed)
      body="💥 **Deploy e rollback falharam**

O deploy falhou e o rollback automático também não foi bem-sucedido. **Intervenção manual necessária.**"
      ;;
    partial)
      body="⚠️ **Deploy falhou — rollback parcial**

Alguns serviços foram restaurados; outros falharam ou não tinham versão anterior registrada."
      ;;
    *)
      body="💥 **Deploy falhou**"
      ;;
  esac

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$details" ]]; then
    body+=$'\n\n'"${details}"
  fi

  body+=$'\n\n'"**Logs completos:** ${run_url}"
  issue_comment "$body"
}

audit_success() {
  issue_comment "✅ **Deploy concluído com sucesso**"
}

audit_success_notify() {
  local services="$1"
  local mentions="$2"
  local changelog_url="${3:-}"
  local changelog_summary="${4:-}"
  local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

  local body="🎉 **Deploy concluído com sucesso**

**Serviços implantados:** \`${services}\`"

  if [[ -n "$mentions" ]]; then
    body+=$'\n\n'"${mentions}"
  fi

  if [[ -n "$changelog_url" ]]; then
    body+=$'\n\n'"**Changelog (diff entre deploys):** ${changelog_url}"
  fi

  if [[ -n "$changelog_summary" ]]; then
    body+=$'\n\n'"<details>"
    body+=$'\n'"<summary>Resumo das mudanças</summary>"
    body+=$'\n'""
    body+=$'\n'"${changelog_summary}"
    body+=$'\n'""
    body+=$'\n'"</details>"
  fi

  body+=$'\n\n'"**Logs do deploy:** ${run_url}"
  issue_comment "$body"
}

audit_failure() {
  local reason="$1"
  issue_comment "💥 **Deploy falhou** — ${reason}

Ver logs: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
}

audit_no_targets() {
  issue_comment "⚠️ **Nenhum serviço identificado** — adicione labels correspondentes aos serviços configurados em \`deploy.config.yaml\`."
}

audit_invalid_type() {
  local expected="$1"
  local actual="$2"
  issue_comment "⚠️ **Issue type inválido** — esperado: \`${expected}\`, atual: \`${actual:-nenhum}\`."
}

audit_state_recorded() {
  local service="$1"
  local previous_ref="$2"
  issue_comment "📋 **Estado registrado** \`${service}\` — versão anterior: \`${previous_ref}\`"
}
