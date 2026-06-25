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

repo_owner() {
  echo "${GITHUB_REPOSITORY%/*}"
}

repo_name() {
  echo "${GITHUB_REPOSITORY#*/}"
}

issue_type_gh_token() {
  if [[ -n "${ORG_ADMIN_TOKEN:-}" ]]; then
    echo "$ORG_ADMIN_TOKEN"
  else
    echo "${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  fi
}

gh_as_issue_type_admin() {
  GH_TOKEN="$(issue_type_gh_token)" gh "$@"
}

gh_graphql_as_issue_type_admin() {
  GH_TOKEN="$(issue_type_gh_token)" gh api graphql "${GRAPHQL_HEADERS[@]}" "$@"
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

issue_type_exists_rest() {
  local type_name="$1"
  local org="$2"
  gh_as_issue_type_admin api "orgs/${org}/issue-types" --jq ".[] | select(.name == \"${type_name}\") | .id" 2>/dev/null || true
}

create_issue_type_rest() {
  local type_name="$1"
  local org="$2"
  gh_as_issue_type_admin api -X POST "orgs/${org}/issue-types" \
    -f name="$type_name" \
    -f is_enabled=true \
    -f description="Deployment requests (managed by gh-deploy-control-with-issues)" \
    -f color="blue" \
    --jq '.name'
}

create_issue_type_graphql() {
  local type_name="$1"
  local org_id="$2"
  gh_graphql_as_issue_type_admin \
    -f query='
    mutation($ownerId: ID!, $name: String!) {
      createIssueType(input: {
        ownerId: $ownerId
        name: $name
        isEnabled: true
        description: "Deployment requests (managed by gh-deploy-control-with-issues)"
      }) {
        issueType { id name }
      }
    }' \
    -f ownerId="$org_id" \
    -f name="$type_name" \
    --jq '.data.createIssueType.issueType.name'
}

sync_issue_type() {
  local type_name org owner_typename org_id existing
  type_name="$(cfg_issue_type)"
  org="$(repo_owner)"

  owner_typename="$(gh api graphql "${GRAPHQL_HEADERS[@]}" \
    -f query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        owner {
          __typename
          ... on Organization { id }
        }
      }
    }' \
    -f owner="$org" \
    -f name="$(repo_name)" \
    --jq '.data.repository.owner | "\(.__typename) \(.id // "")"')"

  org_id=""
  read -r owner_typename org_id <<< "$owner_typename"

  existing="$(issue_type_exists_rest "$type_name" "$org")"
  if [[ -n "$existing" ]]; then
    echo "Issue type exists: ${type_name}"
    return 0
  fi

  if [[ "$owner_typename" != "Organization" ]]; then
    echo "::warning::Issue types cannot be created automatically for user-owned repositories."
    echo "::warning::Use fallback label '$(cfg_fallback_trigger_label)' on deploy issues."
    sync_fallback_trigger_label
    return 0
  fi

  if [[ -z "${ORG_ADMIN_TOKEN:-}" ]]; then
    echo "::error::Cannot create Issue Type '${type_name}' in organization '${org}'."
    echo "::error::GITHUB_TOKEN does not have admin:org permission."
    echo "::error::Add a repository secret ORG_ADMIN_TOKEN with a PAT that has admin:org scope (org owner/admin)."
    echo "::error::See: https://docs.github.com/en/rest/orgs/issue-types#create-issue-type-for-an-organization"
    sync_fallback_trigger_label
    exit 1
  fi

  echo "Creating issue type '${type_name}' in organization '${org}'..."

  if created="$(create_issue_type_rest "$type_name" "$org" 2>&1)"; then
    echo "Created issue type: ${created}"
    return 0
  fi

  echo "REST create failed, trying GraphQL..."
  if [[ -n "$org_id" && "$org_id" != "null" ]]; then
    if created="$(create_issue_type_graphql "$type_name" "$org_id" 2>&1)"; then
      echo "Created issue type: ${created}"
      return 0
    fi
    echo "::error::GraphQL createIssueType failed: ${created}"
  fi

  echo "::error::Failed to create issue type '${type_name}'. Verify ORG_ADMIN_TOKEN has admin:org scope and you are an org administrator."
  sync_fallback_trigger_label
  exit 1
}

sync_labels
sync_issue_type
