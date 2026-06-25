#!/usr/bin/env bash
# Sync GitHub labels and issue types from deploy.config.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/lib/gh-issue.sh"

gh_require

GRAPHQL_HEADERS=(
  -H "GraphQL-Features: issue_types"
  -H "X-Github-Next-Global-ID: 1"
)

gh_graphql() {
  gh api graphql "${GRAPHQL_HEADERS[@]}" "$@"
}

repo_owner() {
  echo "${GITHUB_REPOSITORY%/*}"
}

repo_name() {
  echo "${GITHUB_REPOSITORY#*/}"
}

ensure_label() {
  local name="$1"
  local description="$2"
  local existing
  existing="$(gh label list --json name --jq '.[].name')"

  if echo "$existing" | grep -qx "$name"; then
    echo "Label exists: ${name}"
  else
    gh label create "$name" --description "$description"
    echo "Created label: ${name}"
  fi
}

sync_labels() {
  local service
  for service in $(cfg_service_names); do
    ensure_label "$service" "Deploy target: ${service}"
  done
}

sync_fallback_trigger_label() {
  local fallback
  fallback="$(cfg_fallback_trigger_label)"
  ensure_label "$fallback" "Triggers deployment workflow (fallback when Issue Types are unavailable)"
}

sync_issue_type() {
  local type_name owner_typename org_id existing
  type_name="$(cfg_issue_type)"

  owner_typename="$(gh_graphql \
    -f query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        owner {
          __typename
          ... on Organization { id }
        }
      }
    }' \
    -f owner="$(repo_owner)" \
    -f name="$(repo_name)" \
    --jq '.data.repository.owner | "\(.__typename) \(.id // "")"')"

  local _org_id=""
  read -r owner_typename _org_id <<< "$owner_typename"
  org_id="$_org_id"

  existing="$(gh_graphql \
    -f query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        issueTypes(first: 50) { nodes { id name } }
      }
    }' \
    -f owner="$(repo_owner)" \
    -f name="$(repo_name)" \
    --jq ".data.repository.issueTypes.nodes[]? | select(.name == \"${type_name}\") | .id" 2>/dev/null || true)"

  if [[ -n "$existing" ]]; then
    echo "Issue type exists: ${type_name}"
    return 0
  fi

  if [[ "$owner_typename" != "Organization" ]]; then
    echo "::warning::Issue types cannot be created automatically for user-owned repositories."
    echo "::warning::Create Issue Type '${type_name}' manually in GitHub settings, or use the fallback label '$(cfg_fallback_trigger_label)' on deploy issues."
    sync_fallback_trigger_label
    return 0
  fi

  if [[ -z "$org_id" || "$org_id" == "null" ]]; then
    echo "::warning::Could not resolve organization ID. Create issue type '${type_name}' manually."
    sync_fallback_trigger_label
    return 0
  fi

  if ! gh_graphql \
    -f query='
    mutation($ownerId: ID!, $name: String!) {
      createIssueType(input: {ownerId: $ownerId, name: $name, isEnabled: true}) {
        issueType { id name }
      }
    }' \
    -f ownerId="$org_id" \
    -f name="$type_name" \
    --jq '.data.createIssueType.issueType.name'; then
    echo "::warning::Failed to create issue type '${type_name}'. Ensure the workflow token has organization planning permissions."
    sync_fallback_trigger_label
    return 0
  fi

  echo "Created issue type: ${type_name}"
}

sync_labels
sync_issue_type
