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

## Tutorial: adopt in an existing project

This guide shows how to integrate the platform into a repository that **already has code and pipelines**. Deploys are triggered by issues — this does not replace your existing build/CI, only the production release step.

### Prerequisites

- GitHub repository with Actions enabled
- Permission to create repository secrets (and organization secrets, if applicable)
- **GitHub CLI ≥ 2.94** on runners (`ubuntu-latest` includes it)
- For Issue Types in organization repositories: PAT with `admin:org` scope (see below)

### Step 1 — Copy files from this repository

In your project, copy the structure below from [gh-deploy-control-with-issues](https://github.com/bunx-ai/gh-deploy-control-with-issues):

```text
your-project/
├── deploy.config.yaml              ← create from example (step 2)
├── .github/
│   ├── workflows/
│   │   ├── deploy.yml
│   │   ├── sync-resources.yml
│   │   └── ci.yml                  ← optional, recommended
│   ├── scripts/                    ← entire folder
│   ├── ISSUE_TEMPLATE/             ← optional (sync generates deploy.yml)
│   └── deploy-scripts/             ← only if using strategy: script
└── actions/
    ├── deploy/action.yml           ← required router
    ├── deploy-ssh-docker/
    ├── deploy-cloudflare-pages/
    └── deploy-script/
```

**Via terminal** (with authenticated `gh`):

```bash
# At your repository root
OWNER=bunx-ai
REPO=gh-deploy-control-with-issues
TMP=$(mktemp -d)
gh repo clone "$OWNER/$REPO" "$TMP"

cp -R "$TMP/.github/workflows/deploy.yml" "$TMP/.github/workflows/sync-resources.yml" .github/workflows/
cp -R "$TMP/.github/scripts" .github/
cp -R "$TMP/actions" .
cp "$TMP/examples/deploy.config.example.yaml" deploy.config.yaml
mkdir -p .github/deploy-scripts
cp "$TMP/examples/deploy-scripts/worker.sh" .github/deploy-scripts/   # if using script strategy

# Optional: validation CI
cp "$TMP/.github/workflows/ci.yml" .github/workflows/

rm -rf "$TMP"
```

> **Tip:** do this on a branch (`feat/deploy-via-issues`) and open a PR for review before merging to `main`.

### Step 2 — Configure `deploy.config.yaml`

Edit the file at your project root. Each key under `services` becomes a GitHub **label** and a job in the deploy matrix.

1. List the services you currently publish (API, frontend, worker, etc.)
2. Choose a `strategy` for each (`ssh-docker`, `cloudflare-pages`, or `script`)
3. Fill `config` with **secret names** the workflow will inject (do not put sensitive values in the YAML)
4. Set `deployment.approval.users` to the GitHub usernames of approvers

Minimal example for a Docker backend over SSH:

```yaml
deployment:
  issue_type: Deploy
  fallback_trigger_label: deploy
  approval:
    enabled: true
    users: [your-github-username]
  rollback:
    enabled: true
    automatic: true

services:
  api:
    image: ghcr.io/your-org/your-api
    strategy: ssh-docker
    config:
      ssh_host_secret: PRODUCTION_SSH_HOST
      ssh_user_secret: PRODUCTION_SSH_USERNAME
      ssh_key_secret: PRODUCTION_SSH_KEY
      container_name: api
    healthcheck:
      url: https://api.yourdomain.com/health
```

See `examples/deploy.config.example.yaml` in this repository for all options.

### Step 3 — Map secrets in the workflow

`deploy.config.yaml` references secrets **by name**. The workflow must expose them as environment variables.

Open `.github/workflows/deploy.yml` and add your secrets to each `env:` block in the `deploy`, `healthcheck`, and `rollback` jobs:

```yaml
env:
  PRODUCTION_SSH_HOST: ${{ secrets.PRODUCTION_SSH_HOST }}
  PRODUCTION_SSH_USERNAME: ${{ secrets.PRODUCTION_SSH_USERNAME }}
  PRODUCTION_SSH_KEY: ${{ secrets.PRODUCTION_SSH_KEY }}
  CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
  CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

Only include secrets your services actually use.

### Step 4 — Create secrets in GitHub

Under **Settings → Secrets and variables → Actions**, create the secrets referenced in step 3 (SSH hosts, Cloudflare tokens, etc.).

For **organization** repositories using Issue Type `Deploy`:

| Secret | Scope | Purpose |
|--------|-------|---------|
| `ORG_ADMIN_TOKEN` | PAT with `admin:org` | Create Issue Type in the org (sync workflow) |
| Other secrets | Deploy/infra | SSH, Cloudflare, etc. |

**User-owned** repositories (personal accounts) do not need `ORG_ADMIN_TOKEN` — sync creates the `deploy` label as a fallback.

### Step 5 — Disable the old deploy workflow (if any)

If you had a monolithic workflow (e.g. `cd.yml` that deployed on every push or via issues with `[DEPLOYMENT]`):

1. **Disable or remove** the old workflow to avoid concurrent deploys
2. Move custom logic to:
   - `strategy: script` + a script in `.github/deploy-scripts/`, or
   - a new action in `actions/deploy-<name>/` (see [Adding a custom strategy](#adding-a-custom-strategy))
3. Compare with the table in [Migration from legacy `cd.yml`](#migration-from-legacy-cdyml)

Your build/test CI can stay as-is — this platform only runs when a deploy issue is opened or labeled.

### Step 6 — Sync labels, Issue Type, and template

Merge your branch to `main` and run **Sync Deploy Resources** (Actions → Sync Deploy Resources → Run workflow).

Sync will:

- Create labels for each service (`api`, `frontend`, …)
- Create Issue Type `Deploy` in the org (with `ORG_ADMIN_TOKEN`) or the `deploy` label (fallback)
- Generate/update `.github/ISSUE_TEMPLATE/deploy.yml`

### Step 7 — First test deploy

1. **Issues → New issue → Deploy**
2. Select the test service (e.g. `api`) and describe the reason
3. If `approval.enabled: true`, a user in `approval.users` reacts with 🚀
4. Monitor in **Actions → Deploy**

**Manual test** (without opening a new issue):

```bash
gh workflow run deploy.yml -f issue_number=123
```

Replace `123` with a valid issue number (type `Deploy` + service label).

### Quick checklist

| Item | Done? |
|------|-------|
| `.github/` and `actions/` files copied | ☐ |
| `deploy.config.yaml` with your services | ☐ |
| Secrets mapped in `deploy.yml` | ☐ |
| Secrets created in the repository | ☐ |
| `ORG_ADMIN_TOKEN` (org + Issue Type only) | ☐ |
| Old deploy workflow disabled | ☐ |
| Sync Deploy Resources run | ☐ |
| Test issue with successful deploy | ☐ |

### Coexisting with the rest of your project

- **Monorepo:** one service per key in `services`; labels select what to deploy for that issue
- **Images:** set `image` to the desired tag; the workflow uses the current commit SHA/ref for the changelog — adjust scripts if you always use `latest`
- **Other workflows:** no conflict; deploy uses `concurrency` per issue number
- **Existing issue templates:** the `Deploy` template coexists with yours; `config.yml` only disables blank issues if you copy ours

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

Use the **Deploy** issue template (generated from `deploy.config.yaml` by the sync workflow):

1. **New issue** → **Deploy**
2. Select the service labels and fill in context
3. The template sets **Issue Type** `Deploy` (org) and label `deploy` (fallback)
4. If approval is enabled, an authorized user reacts with 🚀

The template is kept in sync when you change services in `deploy.config.yaml` — run **Sync Deploy Resources** or push to `main`.

**CLI alternative:**

```bash
gh issue create \
  --type Deploy \
  --title "[Deploy] Release v1.2.0" \
  --label deploy \
  --label backend \
  --body "Reason: merged PR #42"
```

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
| `.github/workflows/ci.yml` | Push/PR to `main`, manual | Validate scripts and `deploy.config.yaml` |
| `.github/workflows/sync-resources.yml` | Manual, push to `deploy.config.yaml` or sync scripts | Provision labels, issue types, and deploy issue template |
| `.github/workflows/deploy.yml` | Issue `opened`/`labeled`, manual (with `issue_number`) | Full deploy pipeline |

**Important:** deploy does **not** run on every commit. It triggers when:
1. An issue receives `opened` or `labeled` (with deploy type/label + service labels), or
2. You manually run **Deploy** in Actions with an `issue_number`.

Every push to `main` runs **CI** to validate the repository.

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

## Credits

This platform builds on the original concept and base workflow created by [**@scarletquasar**](https://github.com/scarletquasar). The open-source implementation in this repository extends and generalizes that foundation.

## License

Open source — customize `deploy.config.yaml` and extend strategies for your infrastructure.
