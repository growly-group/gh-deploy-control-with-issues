#!/usr/bin/env bash
# Build changelog compare URL and commit summary between last and current deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

STATE_DIR="${1:-/tmp/deploy-state}"
CURRENT_SHA="${GITHUB_SHA:?GITHUB_SHA required}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"

resolve_git_sha_from_ref() {
  local ref="$1"
  local tag candidate

  [[ -z "$ref" || "$ref" == "unknown" || "$ref" == "null" ]] && return 1

  if git cat-file -e "${ref}^{commit}" 2>/dev/null; then
    git rev-parse "$ref"
    return 0
  fi

  tag="${ref##*:}"
  tag="${tag##@}"
  if [[ "$tag" != "$ref" ]]; then
    if git cat-file -e "${tag}^{commit}" 2>/dev/null; then
      git rev-parse "$tag"
      return 0
    fi
    if [[ "$tag" =~ ^v[0-9] ]] && git rev-parse "refs/tags/${tag}" >/dev/null 2>&1; then
      git rev-parse "refs/tags/${tag}"
      return 0
    fi
  fi

  if [[ "$tag" =~ ^[0-9a-f]{7,40}$ ]]; then
    candidate="$(git rev-parse --verify "${tag}^{commit}" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  return 1
}

resolve_previous_sha() {
  local var_name previous="" file ref

  var_name="$(cfg_changelog_state_variable)"
  if previous="$(gh variable get "$var_name" --repo "$REPO" 2>/dev/null || true)"; then
    if [[ -n "$previous" ]] && resolve_git_sha_from_ref "$previous" >/dev/null 2>&1; then
      resolve_git_sha_from_ref "$previous"
      return 0
    fi
  fi

  if [[ -d "$STATE_DIR" ]]; then
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      ref="$(cat "$file")"
      if previous="$(resolve_git_sha_from_ref "$ref" 2>/dev/null || true)"; then
        [[ -n "$previous" ]] && echo "$previous" && return 0
      fi
    done < <(find "$STATE_DIR" -type f \( -name '*.previous' -o -name '*.deployed' \) 2>/dev/null | sort)
  fi

  return 1
}

build_changelog() {
  if [[ "$(cfg_changelog_enabled)" != "true" ]]; then
    echo "changelog_url=" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT required}"
    echo "changelog_summary=" >> "$GITHUB_OUTPUT"
    return 0
  fi

  local previous_sha current_sha max_commits compare_url summary commit_count
  current_sha="$(git rev-parse "$CURRENT_SHA")"
  max_commits="$(cfg_changelog_max_commits)"

  if ! previous_sha="$(resolve_previous_sha 2>/dev/null || true)" || [[ -z "$previous_sha" ]]; then
    {
      echo "changelog_url="
      echo "changelog_summary=First deploy recorded or previous version not identified in Git."
    } >> "$GITHUB_OUTPUT"
    return 0
  fi

  previous_sha="$(git rev-parse "$previous_sha")"

  if [[ "$previous_sha" == "$current_sha" ]]; then
    {
      echo "changelog_url="
      echo "changelog_summary=No commit changes between the last deploy and this one (same SHA)."
    } >> "$GITHUB_OUTPUT"
    return 0
  fi

  compare_url="${GITHUB_SERVER_URL}/${REPO}/compare/${previous_sha}...${current_sha}"
  commit_count="$(git rev-list --count "${previous_sha}..${current_sha}" 2>/dev/null || echo 0)"
  summary="$(git log --pretty=format:'- %s (%h)' "${previous_sha}..${current_sha}" 2>/dev/null | head -n "$max_commits")"

  if [[ "$commit_count" -gt "$max_commits" ]]; then
    summary+=$'\n'""
    summary+=$'\n'"- ... and $((commit_count - max_commits)) more commit(s). See the full compare link."
  fi

  echo "changelog_url=${compare_url}" >> "$GITHUB_OUTPUT"
  {
    echo "changelog_summary<<EOF"
    echo "${commit_count} commit(s) since last deploy:"
    echo ""
    echo "${summary}"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
}

record_last_deploy_sha() {
  local var_name current_sha
  var_name="$(cfg_changelog_state_variable)"
  current_sha="$(git rev-parse "$CURRENT_SHA")"
  gh variable set "$var_name" --repo "$REPO" --body "$current_sha" 2>/dev/null \
    || echo "::warning::Could not persist ${var_name}. Grant actions variable write permission or set it manually."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-build}" in
    build)
      build_changelog
      ;;
    record)
      record_last_deploy_sha
      ;;
    *)
      echo "Usage: $0 {build|record}" >&2
      exit 1
      ;;
  esac
fi
