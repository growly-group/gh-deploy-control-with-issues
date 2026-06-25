#!/usr/bin/env bash
# Sync GitHub labels and issue types from deploy.config.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/gh-issue.sh
source "${SCRIPT_DIR}/lib/gh-issue.sh"

TEMPLATE_ONLY=false
if [[ "${1:-}" == "--template-only" ]]; then
  TEMPLATE_ONLY=true
fi

if [[ "$TEMPLATE_ONLY" != true ]]; then
  gh_require
fi

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

sync_optional_labels() {
  local service option_id label
  for service in $(cfg_service_names); do
    while IFS= read -r option_id; do
      [[ -z "$option_id" ]] && continue
      label="$(cfg_deploy_option_label "$service" "$option_id")"
      [[ -n "$label" && "$label" != "null" ]] || continue
      ensure_label "$label" "Deploy option (${service}): ${option_id}"
    done < <(cfg_service_deploy_option_ids "$service")
  done
}

sync_fallback_trigger_label() {
  local fallback
  fallback="$(cfg_fallback_trigger_label)"
  ensure_label "$fallback" "Triggers deployment workflow (fallback when Issue Types are unavailable)"
}

issue_type_exists_graphql() {
  local type_name="$1"
  local org="$2"
  gh api graphql "${GRAPHQL_HEADERS[@]}" \
    -f query='
    query($org: String!) {
      organization(login: $org) {
        issueTypes(first: 25) {
          nodes {
            name
            isEnabled
          }
        }
      }
    }' \
    -f org="$org" \
    --jq --arg typeName "$type_name" '
      [.data.organization.issueTypes.nodes[]
        | select(.name == $typeName and .isEnabled == true)
        | .name][0] // empty' 2>/dev/null || true
}

issue_type_exists_rest() {
  local type_name="$1"
  local org="$2"
  local response found

  if ! response="$(gh_as_issue_type_admin api "orgs/${org}/issue-types" 2>/dev/null)"; then
    return 1
  fi
  if ! echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
    return 1
  fi

  found="$(echo "$response" | jq -r --arg name "$type_name" '
    [.[] | select(.name == $name and .is_enabled == true) | .id][0] // empty')"
  [[ -n "$found" ]]
}

issue_type_exists() {
  local type_name="$1"
  local org="$2"
  local found

  found="$(issue_type_exists_graphql "$type_name" "$org")"
  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi

  if issue_type_exists_rest "$type_name" "$org"; then
    echo "$type_name"
    return 0
  fi

  return 1
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

  existing="$(issue_type_exists "$type_name" "$org" || true)"
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
  else
    echo "REST create failed, trying GraphQL..."
    if [[ -n "$org_id" && "$org_id" != "null" ]]; then
      if created="$(create_issue_type_graphql "$type_name" "$org_id" 2>&1)"; then
        echo "Created issue type: ${created}"
      else
        echo "::error::GraphQL createIssueType failed: ${created}"
        sync_fallback_trigger_label
        exit 1
      fi
    else
      echo "::error::Failed to create issue type '${type_name}' via REST: ${created}"
      sync_fallback_trigger_label
      exit 1
    fi
  fi

  if [[ -n "$(issue_type_exists "$type_name" "$org" || true)" ]]; then
    echo "Verified issue type: ${type_name}"
    return 0
  fi

  echo "::error::Issue type '${type_name}' was not found after creation attempt."
  sync_fallback_trigger_label
  exit 1
}

sync_issue_template() {
  local template_dir=".github/ISSUE_TEMPLATE"
  local template_file="${template_dir}/deploy.yml"
  local type_name fallback service option_id intro_line checkbox description

  type_name="$(cfg_issue_type)"
  fallback="$(cfg_fallback_trigger_label)"

  mkdir -p "$template_dir"

  {
    printf '%s\n' \
      "# Generated by .github/scripts/sync-resources.sh — edit deploy.config.yaml and re-run sync." \
      "name: Deploy" \
      "description: Request deployment of one or more services" \
      'title: "[Deploy] "' \
      "type: ${type_name}" \
      "labels:" \
      "  - ${fallback}" \
      "body:" \
      "  - type: markdown" \
      "    attributes:" \
      "      value: |"

    while IFS= read -r intro_line || [[ -n "$intro_line" ]]; do
      printf '        %s\n' "$intro_line"
    done < <(cfg_issue_template_intro | sed -e :a -e '/^\s*$/{$d;N;ba' -e '}')

    printf '%s\n' \
      "" \
      "  - type: checkboxes" \
      "    id: services" \
      "    attributes:" \
      "      label: Services" \
      "      description: $(cfg_issue_template_services_description)" \
      "      options:"

    for service in $(cfg_service_names); do
      printf '        - label: %s\n' "$service"
    done

    printf '%s\n' \
      "    validations:" \
      "      required: true"

    for service in $(cfg_service_names); do
      if ! cfg_service_has_deploy_options "$service"; then
        continue
      fi
      while IFS= read -r option_id; do
        [[ -z "$option_id" ]] && continue
        checkbox="$(cfg_deploy_option_checkbox "$service" "$option_id")"
        description="$(cfg_deploy_option_description "$service" "$option_id")"
        printf '%s\n' \
          "" \
          "  - type: checkboxes" \
          "    id: ${service}-options-${option_id}" \
          "    attributes:" \
          "      label: ${service} — ${option_id}" \
          "      description: ${description}" \
          "      options:" \
          "        - label: ${checkbox}"
      done < <(cfg_service_deploy_option_ids "$service")
    done

    printf '%s\n' \
      "" \
      "  - type: textarea" \
      "    id: reason" \
      "    attributes:" \
      "      label: Reason / context" \
      "      description: PR, release, hotfix, etc." \
      "      placeholder: \"$(cfg_issue_template_reason_placeholder)\"" \
      "    validations:" \
      "      required: true" \
      "" \
      "  - type: textarea" \
      "    id: notes" \
      "    attributes:" \
      "      label: Notes (optional)" \
      "      description: $(cfg_issue_template_notes_description)"
  } > "$template_file"

  echo "Generated issue template: ${template_file}"
}

if [[ "$TEMPLATE_ONLY" == true ]]; then
  sync_issue_template
  exit 0
fi

sync_labels
sync_optional_labels
sync_fallback_trigger_label
sync_issue_type
sync_issue_template
