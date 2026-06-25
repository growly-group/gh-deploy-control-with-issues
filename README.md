# gh-deploy-control-with-issues

Open source deployment platform for GitHub Actions. Trigger production deploys from GitHub Issues using **Issue Types** and **service labels**, with optional approval via reactions, configurable health checks, and manual/automatic rollback.

## Features

- **Centralized configuration** in `deploy.config.yaml` — no hardcoded service names in workflows
- **Label-based deploy targets** — each service key becomes a GitHub label
- **Pluggable deploy strategies** per service: `ssh-docker`, `cloudflare-pages`, `script`
- **Approval gate** via 🚀 reaction from authorized users
- **Rejection** via 👎 reaction
- **Manual rollback** via 👀 reaction
- **Automatic rollback** on deploy or health check failure (configurable)
- **Rollback notifications** on the issue with @mentions, failure details, and log excerpts
- **Audit trail** posted as issue comments
- **GitHub CLI first** — `gh`, `gh label`, `gh issue`, `gh api`

## Quick start

### 1. Configure services

Copy the example and edit `deploy.config.yaml` at the repository root:

```bash
cp examples/deploy.config.example.yaml deploy.config.yaml
```

```yaml
deployment:
  issue_type: Deploy
  approval:
    enabled: true
    users: [techlead, sre]
  rollback:
    enabled: true
    automatic: true
  healthcheck:
    enabled: true
    timeout: 300
    retries: 10
  observability:
    include_failed_logs: true
    max_log_lines: 40

services:
  backend:
    image: ghcr.io/company/backend
    strategy: ssh-docker
    config:
      ssh_host_secret: PRODUCTION_SSH_HOST
      ssh_user_secret: PRODUCTION_SSH_USERNAME
      ssh_key_secret: PRODUCTION_SSH_KEY
      container_name: backend
    healthcheck:
      url: https://api.example.com/health
```

### 2. Sync GitHub resources

Run the **Sync Deploy Resources** workflow (or push `deploy.config.yaml` to `main`):

- Creates labels for each service (`frontend`, `backend`, `worker`, …)
- **Organization repos:** creates Issue Type `Deploy` via REST API (requires secret `ORG_ADMIN_TOKEN`)
- **User-owned repos:** Issue Types cannot be created via API — the workflow creates a fallback label `deploy` instead

### Organization setup (Issue Types)

`GITHUB_TOKEN` **cannot** create Issue Types — it lacks `admin:org` scope. For organization repositories:

1. Create a [Personal Access Token](https://github.com/settings/tokens) with **`admin:org`** scope (org owner/admin required)
2. Add it as repository secret: **`ORG_ADMIN_TOKEN`**
3. Run **Sync Deploy Resources** again

Without `ORG_ADMIN_TOKEN`, the sync workflow fails with a clear error and creates the fallback label `deploy` so deploys can still work via label.

Requires **GitHub CLI ≥ 2.94** for issue type support.

### 3. Map secrets in the deploy workflow

Edit `.github/workflows/deploy.yml` and add secrets referenced in your config to the `deploy` and `rollback` job `env` blocks:

```yaml
env:
  PRODUCTION_SSH_HOST: ${{ secrets.PRODUCTION_SSH_HOST }}
  PRODUCTION_SSH_USERNAME: ${{ secrets.PRODUCTION_SSH_USERNAME }}
  PRODUCTION_SSH_KEY: ${{ secrets.PRODUCTION_SSH_KEY }}
```

### 4. Open a deploy issue

1. Create an issue with **Issue Type**: `Deploy` (org repos) **or** label `deploy` (user repos)
2. Add labels for the services to deploy (e.g. `frontend`, `backend`)
3. If approval is enabled, an authorized user reacts with 🚀

## Reaction reference

| Emoji | Meaning |
|-------|---------|
| 🚀 | Approve deploy |
| 👎 | Reject deploy (closes issue) |
| 👀 | Request manual rollback |

## Deploy strategies

| Strategy | Description | Config keys |
|----------|-------------|-------------|
| `ssh-docker` | SSH to host, `docker pull`, restart container | `ssh_host_secret`, `ssh_user_secret`, `ssh_key_secret`, `ssh_port_var`, `container_name` |
| `cloudflare-pages` | Deploy static directory via Wrangler | `project_name`, `directory` (+ `CLOUDFLARE_*` secrets in workflow) |
| `script` | Run a repository script | `script` (path relative to repo root) |

### Adding a custom strategy

1. Create `actions/deploy-<name>/action.yml` with outputs: `previous_ref`, `deployed_ref`, `deploy_status`, `failure_detail`
2. Register the strategy in `actions/deploy/action.yml`
3. Set `strategy: <name>` in `deploy.config.yaml`

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `.github/workflows/sync-resources.yml` | `workflow_dispatch`, push to `deploy.config.yaml` | Provision labels and issue types |
| `.github/workflows/deploy.yml` | Issue `opened`, `labeled` | Full deploy pipeline |

## Architecture

```
Issue (Type: Deploy + labels)
  → setup (validate + matrix)
  → wait-approval (optional, poll 🚀/👎)
  → deploy (matrix per service → strategy action)
  → healthcheck (matrix)
  → rollback-notify (comment on issue with failure details + @mentions)
  → rollback (automatic on failure)
  → finalize (success notification + changelog + close issue)
```

## Rollback notifications

When a deploy or health check fails and automatic rollback is enabled:

1. **Immediate alert** on the issue with @mentions (issue author + `approval.users`)
2. **Failure details** per service (HTTP status, deploy error, etc.) in collapsible `<details>` blocks
3. **Log excerpt** from failed workflow steps via `gh run view --log-failed`
4. **Per-service rollback updates** as each service is restored
5. **Final summary** distinguishing:
   - Environment restored (`deploy:rolled-back` label, issue stays open)
   - Rollback also failed (manual intervention required)
   - Partial rollback (some services could not be restored)

Configure log inclusion in `deploy.config.yaml`:

```yaml
deployment:
  observability:
    notify_on_success: true
    include_failed_logs: true
    max_log_lines: 40
    max_log_chars: 3500
    changelog:
      enabled: true
      max_commits: 20
      state_variable: DEPLOY_LAST_GIT_SHA
```

## Success notifications

When deploy and health checks succeed:

1. Optional success comment on the issue (`notify_on_success`, default **on**) with @mentions
2. **Changelog link** comparing the current commit with the last successful deploy (`changelog.enabled`, default **on**)
3. Collapsible commit summary in the issue comment
4. Issue is closed automatically

The last deployed Git SHA is stored in the repository variable `DEPLOY_LAST_GIT_SHA` (configurable via `changelog.state_variable`). The workflow needs `actions: write` permission on the finalize job to persist it. On the first deploy, the changelog falls back to parsing image tags from the previous deployment state.

Disable success notifications:

```yaml
deployment:
  observability:
    notify_on_success: false
```

## Migration from legacy `cd.yml`

| Legacy | New platform |
|--------|--------------|
| `[DEPLOYMENT]` title prefix | Issue Type `Deploy` |
| Checkbox targets in issue body | Service labels from config |
| `vars.ALLOWED_USERS_*` | `deployment.approval.users` |
| Per-service hardcoded jobs | Dynamic matrix + strategies |
| `curl` GitHub API calls | `gh issue comment`, `gh issue close` |
| Inline SSH health checks | `healthcheck.sh` + config |

The legacy monolithic workflow (`cd.yml`) has been removed. See `examples/` for reference configuration.

## Requirements

- GitHub Actions
- GitHub CLI (`gh`) on runners (pre-installed on `ubuntu-latest`)
- `yq` (installed by workflows)
- Repository permissions: `issues: write`, `contents: read`, `deployments: write`

## License

Open source — customize `deploy.config.yaml` and extend strategies for your infrastructure.
