# GitHub Repository Management (OpenTofu)

This module manages the GitHub repository settings and branch protection rules
for this repo as code via the `integrations/github` Terraform provider.

## Required GitHub Token Scopes

The `github_token` variable must be a GitHub Personal Access Token (classic) or
a GitHub App installation token with **all** of the following scopes:

| Scope                           | Reason                             |
| ------------------------------- | ---------------------------------- |
| `repo`                          | Read/write repository settings     |
| `admin:repo_hook`               | Manage webhooks                    |
| `admin:org` (if org-owned repo) | Manage org-level branch protection |

## Security & Hardening Architecture

The repository configuration implements defense-in-depth across multiple layers:

### 1. Branch Protection & Main Ruleset

- **Linear History:** Enforces squash merges only; merge commits and rebase commits are prohibited.
- **Head Branch Auto-Deletion:** Automatically deletes branches upon PR merge.
- **GitHub Merge Queue (`STD-CI-68`):** Enabled on public repositories by default (override with the nullable root `enable_merge_queue` variable; `merge_method = "SQUASH"`, `grouping_strategy = "ALLGREEN"`, `min_entries_to_merge = 1`, `min_entries_to_merge_wait_minutes = 0`, `max_entries_to_merge = 5`, `max_entries_to_build = 5`, `check_response_timeout_minutes = 60`), allowing concurrent PRs and Renovate batches to be speculatively validated and merged atomically without manual rebasing.
- **CI vs. Operational Environments (`STD-CI-23`):** The `ci` environment (synthetic-only `SOPS_AGE_KEY_CI`) uses custom deployment branch policies that allow only `main` (push, schedule), `refs/pull/*/merge` (`pull_request`) and, while the merge queue is enabled, `gh-readonly-queue/main/*` (`merge_group`). `protected_branches = true` is not used because `main` is protected by a ruleset rather than classic branch protection, and GitHub then lets every branch deploy. Both `backup` and `ops` use `custom_branch_policies = true` restricted exclusively to `main` (`pattern = "main"`) and reject `SOPS_AGE_KEY_CI`; `code_quality` has no branch policy.
- **Ruleset Bypass Actors** (owner decision D6):
  - **Organization owners** (`actor_type = "OrganizationAdmin"`, `bypass_mode = "always"`, no `actor_id`, because GitHub stores `null` for this actor type) — allows the owner's local fast-forward merges, guarded by the `pre-push` hook (`ALLOW_MAIN_PUSH=1`).
  - **Repository Administrator** (`actor_id = 5`, `actor_type = "RepositoryRole"`, `bypass_mode = "pull_request"`) — may bypass only through a pull request.
  - Automated bots (Dependabot and Renovate) are **not** bypass actors; they auto-merge natively via repository `allow_auto_merge = true` and the `main` Merge Queue only after all required CI checks (`CI Gate`) pass green, preventing any bypass of CI gates or direct pushes to `main`.

### 2. GitHub Actions Permissions & SHA Pinning

- **Allowed Actions (`STD-CI-13`, `STD-OT-48`):** Restricted to `selected` actions only with:
  - `github_owned_allowed = true` (official `actions/*` and `github/*` actions)
  - `verified_allowed = false` (broad Marketplace "verified creator" trust disabled)
  - `patterns_allowed = var.allowed_action_patterns` (explicit third-party action allowlist)
- **Full-Length Commit SHA Pinning:** Enforced repository-wide via `sha_pinning_required = true`. Every action reference must use an immutable 40-character commit SHA.
- **Least-Privilege Workflow Permissions:** Defaults to `read` permissions across all workflows (`default_workflow_permissions = "read"`).
- **PR Approval Lockdown:** Workflows are forbidden from approving pull requests (`can_approve_pull_request_reviews = false`).

### 3. Deploy Keys (`STD-OT-16`, `STD-OT-47`)

- Declarative deploy keys are sourced from `github.deploy_keys` in SOPS (`secrets/credentials.sops.yaml`) or `var.deploy_keys` (default `{}`).
- Every deploy key must be read-only (`read_only = true`, `STD-OT-47`) and must not contain an `@` email comment (`STD-OT-16`).

### 4. REST API Synchronization (`mise run github:sync`)

Settings not yet exposed via the `integrations/github` provider are managed via an idempotent REST API sync script (`scripts/sync-github-repo-settings.sh`) backed by Bats tests:

- **Release Immutability:** Prevents deletion or modification of published releases and tags (`PUT /repos/$REPO/immutable-releases`).
- **Artifact & Log Retention:** Capped at 14 days (`PUT /repos/$REPO/actions/permissions/artifact-and-log-retention`).
- **External Contributor Approval:** Set to `all_external_contributors` for fork pull requests (`PUT /repos/$REPO/actions/permissions/fork-pr-contributor-approval`).
- **Security & Secret Push Protection:** Enforces Dependabot alerts and Secret Scanning Push Protection.

Run the sync task:

```bash
mise run github:sync
```

### 5. Multi-Ecosystem CodeQL & Security Scanning Workflow

Scheduled and PR security analysis via `.github/workflows/codeql.yml`:

- **Native CodeQL Analysis:** Scans GitHub Actions workflow definitions (`actions`) and Python code (`python`).
- **Multi-Ecosystem IaC Scanning:** Trivy scans OpenTofu, Ansible, and configuration files, outputting SARIF reports to GitHub Security (`trivy-iac`).
- **Shell Script Security:** ShellCheck scans all shell scripts, converted to SARIF format via `scripts/format-shellcheck-sarif.py` and uploaded to GitHub Security (`shellcheck`).

## Usage

```bash
# Initialise (uses local state — see infrastructure/bootstrap/ for remote state setup)
tofu init

# Preview changes
tofu plan -var="github_token=$(sops -d secrets/credentials.sops.yaml | yq .github.token)"

# Apply
tofu apply -var="github_token=$(sops -d secrets/credentials.sops.yaml | yq .github.token)"
```

## Inputs

See `variables.tf` for full descriptions. All variables are `sensitive = true`.

| Name              | Description                                |
| ----------------- | ------------------------------------------ |
| `github_token`    | PAT or App token with repo + admin scopes  |
| `github_owner`    | GitHub org or username owning this repo    |
| `repository_name` | Repository name (default: `homelab-infra`) |

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version |
| ------------------------------------------------------------------------ | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | 1.16.6  |
| <a name="requirement_external"></a> [external](#requirement_external)    | 2.3.5   |
| <a name="requirement_github"></a> [github](#requirement_github)          | 6.13.0  |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                | 1.4.1   |

## Providers

| Name                                                            | Version |
| --------------------------------------------------------------- | ------- |
| <a name="provider_external"></a> [external](#provider_external) | 2.3.5   |

## Modules

| Name                                                              | Source               | Version |
| ----------------------------------------------------------------- | -------------------- | ------- |
| <a name="module_repository"></a> [repository](#module_repository) | ./modules/repository | n/a     |

## Resources

| Name                                                                                                                         | Type        |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [external_external.sops_github](https://registry.terraform.io/providers/hashicorp/external/2.3.5/docs/data-sources/external) | data source |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                                   | Type                                                                                         | Default                                                                                                                                                   | Required |
| -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | :------: |
| <a name="input_allow_merge_commit"></a> [allow\_merge\_commit](#input_allow_merge_commit)                            | Whether to allow merge commits on the repository (must be false to enforce linear trunk-based history).                                                       | `bool`                                                                                       | `false`                                                                                                                                                   |    no    |
| <a name="input_allow_rebase_merge"></a> [allow\_rebase\_merge](#input_allow_rebase_merge)                            | Whether to allow rebase merge on the repository (must be false to enforce squash-merge policy).                                                               | `bool`                                                                                       | `false`                                                                                                                                                   |    no    |
| <a name="input_allowed_action_patterns"></a> [allowed\_action\_patterns](#input_allowed_action_patterns)             | Explicit allowlist of third-party GitHub Action patterns permitted to run in managed repositories (R2-GOV-01).                                                | `list(string)`                                                                               | <pre>[<br/> "cloudflare/wrangler-action@_",<br/> "gitleaks/gitleaks-action@_",<br/> "jdx/mise-action@_",<br/> "step-security/harden-runner@_"<br/>]</pre> |    no    |
| <a name="input_backup_secrets"></a> [backup\_secrets](#input_backup_secrets)                                         | A map of sensitive secrets to inject into the 'backup' environment (restricted to main).                                                                      | `map(string)`                                                                                | `{}`                                                                                                                                                      |    no    |
| <a name="input_ci_secrets"></a> [ci\_secrets](#input_ci_secrets)                                                     | A map of sensitive secrets to inject into the 'ci' environment.                                                                                               | `map(string)`                                                                                | `{}`                                                                                                                                                      |    no    |
| <a name="input_deploy_keys"></a> [deploy\_keys](#input_deploy_keys)                                                  | Deploy keys to register on the primary infra repository (overrides SOPS github.config.deploy\_keys when non-empty).                                           | <pre>map(object({<br/> title = string<br/> key = string<br/> read_only = bool<br/> }))</pre> | `{}`                                                                                                                                                      |    no    |
| <a name="input_enable_merge_queue"></a> [enable\_merge\_queue](#input_enable_merge_queue)                            | Override for GitHub Merge Queue on each managed repository's main ruleset. Null (default) enables it on public repositories only, the GitHub Free plan limit. | `bool`                                                                                       | `null`                                                                                                                                                    |    no    |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input_enable_prevent_destroy)                | Whether to prevent destruction of critical GitHub resources (defaults to true for production safety).                                                         | `bool`                                                                                       | `true`                                                                                                                                                    |    no    |
| <a name="input_github_owner"></a> [github\_owner](#input_github_owner)                                               | The target GitHub organization or user account (overrides SOPS if provided).                                                                                  | `string`                                                                                     | `""`                                                                                                                                                      |    no    |
| <a name="input_github_token"></a> [github\_token](#input_github_token)                                               | Personal Access Token for GitHub authentication (overrides SOPS if provided).                                                                                 | `string`                                                                                     | `""`                                                                                                                                                      |    no    |
| <a name="input_ops_secrets"></a> [ops\_secrets](#input_ops_secrets)                                                  | A map of sensitive secrets to inject into the 'ops' environment (restricted to main).                                                                         | `map(string)`                                                                                | `{}`                                                                                                                                                      |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file holding github configuration (defaults to production credentials).                                                | `string`                                                                                     | `"../../secrets/credentials.sops.yaml"`                                                                                                                   |    no    |
| <a name="input_sops_age_key_ci"></a> [sops\_age\_key\_ci](#input_sops_age_key_ci)                                    | Override for the single CI age identity uploaded to GitHub. Empty (default) reads production SOPS `github.ci_age_key`.                                        | `string`                                                                                     | `""`                                                                                                                                                      |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed.            | `string`                                                                                     | n/a                                                                                                                                                       |   yes    |

## Outputs

| Name                                                                                           | Description                                                 |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| <a name="output_deploy_keys"></a> [deploy\_keys](#output_deploy_keys)                          | Deploy keys registered on the infra repository.             |
| <a name="output_repositories"></a> [repositories](#output_repositories)                        | Map of managed GitHub repositories and their metadata.      |
| <a name="output_repository_html_url"></a> [repository\_html\_url](#output_repository_html_url) | The HTML URL of the primary infra GitHub repository.        |
| <a name="output_repository_node_id"></a> [repository\_node\_id](#output_repository_node_id)    | The GraphQL Node ID of the primary infra GitHub repository. |

<!-- END_TF_DOCS -->
