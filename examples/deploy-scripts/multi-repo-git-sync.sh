#!/usr/bin/env bash
# Example multi-repo script deploy — syncs a separate application repository.
#
# Environment variables provided by the deploy platform:
#   SERVICE        - service name from deploy.config.yaml
#   IMAGE          - ref to deploy (git SHA/tag) or rollback target when ROLLBACK_MODE=true
#   CONFIG_JSON    - JSON strategy config (includes optional git_remote, git_branch)
#   ROLLBACK_MODE  - "true" when executing a rollback
#   PREVIOUS_REF   - ref recorded before deploy (for rollback context)
#
# Optional config keys (in deploy.config.yaml under services.<name>.config):
#   git_remote     - SSH/HTTPS remote for the application repo (default: workflow checkout)
#   git_branch     - branch to reset to (default: main)
#   marker_file    - file that must exist after sync to validate checkout (default: auto-detect)
#
# Override git_remote at runtime via GIT_REMOTE env var if needed.
#
# Ref recording (read after successful script exit):
#   echo "$PREVIOUS_REF" > "/tmp/deploy-previous-ref-${SERVICE}"
#   echo "$DEPLOYED_REF" > "/tmp/deploy-deployed-ref-${SERVICE}"
set -euo pipefail

WORKDIR="${DEPLOY_WORKDIR:-/tmp/deploy-app-${SERVICE}}"
GIT_REMOTE="${GIT_REMOTE:-$(echo "$CONFIG_JSON" | jq -r '.git_remote // empty')}"
GIT_BRANCH="${GIT_BRANCH:-$(echo "$CONFIG_JSON" | jq -r '.git_branch // "main"')}"
MARKER_FILE="${MARKER_FILE:-$(echo "$CONFIG_JSON" | jq -r '.marker_file // empty')}"

ensure_git_origin() {
  local remote="$1"
  if git -C "$WORKDIR" remote get-url origin &>/dev/null; then
    git -C "$WORKDIR" remote set-url origin "$remote"
  else
    git -C "$WORKDIR" remote add origin "$remote"
  fi
}

safe_rollback_reset() {
  local ref="$1"
  local branch="$2"

  git -C "$WORKDIR" fetch origin
  if git -C "$WORKDIR" merge-base --is-ancestor "$ref" "origin/${branch}" 2>/dev/null; then
    git -C "$WORKDIR" reset --hard "$ref"
  else
    echo "::warning::Rollback ref ${ref} not on origin/${branch}; using origin/${branch}"
    git -C "$WORKDIR" reset --hard "origin/${branch}"
  fi
}

resolve_marker() {
  if [[ -n "$MARKER_FILE" && "$MARKER_FILE" != "null" ]]; then
    echo "$MARKER_FILE"
    return
  fi
  for candidate in package.json go.mod Cargo.toml pyproject.toml; do
    if [[ -f "${WORKDIR}/${candidate}" ]]; then
      echo "$candidate"
      return
    fi
  done
  echo "package.json"
}

record_refs() {
  local previous="$1" deployed="$2"
  echo "$previous" > "/tmp/deploy-previous-ref-${SERVICE}"
  echo "$deployed" > "/tmp/deploy-deployed-ref-${SERVICE}"
}

if [[ "${ROLLBACK_MODE:-false}" == "true" ]]; then
  target_ref="${IMAGE}"
  if [[ ! -d "$WORKDIR/.git" ]]; then
    echo "::error::Rollback workdir not found: ${WORKDIR}" >&2
    exit 1
  fi
  if [[ -n "$GIT_REMOTE" && "$GIT_REMOTE" != "null" ]]; then
    ensure_git_origin "$GIT_REMOTE"
  fi
  safe_rollback_reset "$target_ref" "$GIT_BRANCH"
  marker="$(resolve_marker)"
  if [[ ! -f "${WORKDIR}/${marker}" ]]; then
    echo "::error::Expected marker file missing after rollback: ${WORKDIR}/${marker}" >&2
    exit 1
  fi
  echo "Rolled back ${SERVICE} to $(git -C "$WORKDIR" rev-parse HEAD)"
  exit 0
fi

PREVIOUS_REF="${PREVIOUS_REF:-unknown}"
if [[ -d "$WORKDIR/.git" ]]; then
  PREVIOUS_REF="$(git -C "$WORKDIR" rev-parse HEAD)"
fi

if [[ -n "$GIT_REMOTE" && "$GIT_REMOTE" != "null" ]]; then
  if [[ ! -d "$WORKDIR/.git" ]]; then
    mkdir -p "$WORKDIR"
    git clone "$GIT_REMOTE" "$WORKDIR"
  else
    ensure_git_origin "$GIT_REMOTE"
  fi
  git -C "$WORKDIR" fetch origin "$GIT_BRANCH"
  git -C "$WORKDIR" reset --hard "origin/${GIT_BRANCH}"
else
  echo "No git_remote in config — using workflow checkout at ${GITHUB_WORKSPACE:-.}"
  WORKDIR="${GITHUB_WORKSPACE:-.}"
  PREVIOUS_REF="$(git -C "$WORKDIR" rev-parse HEAD^ 2>/dev/null || echo unknown)"
  git -C "$WORKDIR" fetch origin "$GIT_BRANCH" 2>/dev/null || true
  git -C "$WORKDIR" reset --hard "origin/${GIT_BRANCH}" 2>/dev/null || git -C "$WORKDIR" reset --hard "$IMAGE"
fi

DEPLOYED_REF="$(git -C "$WORKDIR" rev-parse HEAD)"
marker="$(resolve_marker)"
if [[ ! -f "${WORKDIR}/${marker}" ]]; then
  echo "::error::Expected marker file missing after sync: ${WORKDIR}/${marker}" >&2
  exit 1
fi

record_refs "$PREVIOUS_REF" "$DEPLOYED_REF"
echo "Deployed ${SERVICE} at ${DEPLOYED_REF} (${marker} present)"
