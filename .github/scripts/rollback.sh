#!/usr/bin/env bash
# Rollback a service to a previous image reference.
set -euo pipefail

SERVICE="${1:?service name required}"
PREVIOUS_REF="${2:?previous ref required}"
REASON="${3:-rollback requested}"
ACTOR="${4:-automatic}"
FAILED_REF="${5:-unknown}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/audit.sh
source "${SCRIPT_DIR}/lib/audit.sh"

STRATEGY="$(cfg_service_field "$SERVICE" "strategy")"
CONFIG_JSON="$(cfg_json ".services.${SERVICE}.config // {}")"
IMAGE="$(cfg_service_field "$SERVICE" "image")"
FAILED_REF="${FAILED_REF:-$IMAGE}"

if [[ "$PREVIOUS_REF" == "unknown" || -z "$PREVIOUS_REF" ]]; then
  audit_rollback_skipped "$SERVICE" "no previous version recorded"
  echo "rollback_status=skipped" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
  exit 0
fi

audit_rollback_started "$SERVICE" "$PREVIOUS_REF" "$FAILED_REF"

echo "Rolling back ${SERVICE} (${STRATEGY}) to ${PREVIOUS_REF}"

set +e
rollback_err=""
case "$STRATEGY" in
  ssh-docker)
    SSH_HOST_SECRET="$(echo "$CONFIG_JSON" | jq -r '.ssh_host_secret')"
    SSH_USER_SECRET="$(echo "$CONFIG_JSON" | jq -r '.ssh_user_secret')"
    SSH_KEY_SECRET="$(echo "$CONFIG_JSON" | jq -r '.ssh_key_secret')"
    SSH_PORT_VAR="$(echo "$CONFIG_JSON" | jq -r '.ssh_port_var // empty')"
    CONTAINER_NAME="$(echo "$CONFIG_JSON" | jq -r '.container_name')"

    SSH_HOST="${!SSH_HOST_SECRET:?missing ssh host secret}"
    SSH_USER="${!SSH_USER_SECRET:?missing ssh user secret}"
    SSH_KEY="${!SSH_KEY_SECRET:?missing ssh key secret}"
    SSH_PORT="${SSH_PORT_VAR:+${!SSH_PORT_VAR}}"
    SSH_PORT="${SSH_PORT:-22}"

    mkdir -p ~/.ssh
    echo "$SSH_KEY" > ~/.ssh/deploy_key
    chmod 600 ~/.ssh/deploy_key

    if ! ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" bash -s 2>/tmp/rollback.err <<EOF
set -euo pipefail
sudo docker pull "${PREVIOUS_REF}"
if sudo docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  sudo docker stop "${CONTAINER_NAME}" || true
  sudo docker rm "${CONTAINER_NAME}" || true
fi
sudo docker run -d --name "${CONTAINER_NAME}" --restart unless-stopped "${PREVIOUS_REF}"
EOF
    then
      rollback_err="$(tail -20 /tmp/rollback.err 2>/dev/null || echo "SSH/docker rollback failed")"
    fi
    ;;
  script)
    SCRIPT_PATH="$(echo "$CONFIG_JSON" | jq -r '.script')"
    export SERVICE IMAGE="$PREVIOUS_REF" ROLLBACK_MODE=true CONFIG_JSON
    if ! bash "$SCRIPT_PATH" 2>/tmp/rollback.err; then
      rollback_err="$(tail -20 /tmp/rollback.err 2>/dev/null || echo "script rollback failed")"
    fi
    ;;
  cloudflare-pages)
    rollback_err="cloudflare-pages rollback is not automated; redeploy previous build manually"
    ;;
  *)
    rollback_err="Unknown strategy: ${STRATEGY}"
    ;;
esac
set -e

if [[ -n "$rollback_err" ]]; then
  audit_rollback_failed "$SERVICE" "$PREVIOUS_REF" "$rollback_err" "$ACTOR"
  echo "rollback_status=failure" >> "$GITHUB_OUTPUT"
  exit 1
fi

audit_rollback "$SERVICE" "$PREVIOUS_REF" "$REASON" "$ACTOR"
echo "rollback_status=success" >> "$GITHUB_OUTPUT"
