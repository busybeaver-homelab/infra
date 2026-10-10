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
- **Ruleset Bypass Actors:** Configured with `bypass_mode = "always"` for:
  - **Repository Administrator** (`actor_id = 5`, `actor_type = "RepositoryRole"`) — allows direct pushes for administrative operations.
  - **Dependabot** (`actor_id = 29110`, `actor_type = "Integration"`) — authorized for automated PR merge upon CI status check passage.
  - **Renovate** (`actor_id = 2740`, `actor_type = "Integration"`) — authorized for automated PR merge upon CI status check passage.

### 2. GitHub Actions Permissions & SHA Pinning

- **Allowed Actions:** Restricted to `selected` actions only, inheriting organization allowlists with:
  - `github_owned_allowed = true` (official GitHub actions)
  - `verified_allowed = true` (verified Marketplace creators)
  - `patterns_allowed = ["busybeaver-homelab/*"]` (internal organization workflows)
- **Full-Length Commit SHA Pinning:** Enforced repository-wide via `sha_pinning_required = true`. Every action reference must use an immutable 40-character commit SHA.
- **Least-Privilege Workflow Permissions:** Defaults to `read` permissions across all workflows (`default_workflow_permissions = "read"`).
- **PR Approval Lockdown:** Workflows are forbidden from approving pull requests (`can_approve_pull_request_reviews = false`).

### 3. Deploy Keys

- Declarative deploy keys managed through `var.deploy_keys` and imported into OpenTofu state.
- Primary key: `work-laptop` with read/write access (`read_only = false`) for authenticated administrative deployments.

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

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.1.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.1.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_repository"></a> [repository](#module\_repository) | ./modules/repository | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [sops_file.secrets](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_merge_commit"></a> [allow\_merge\_commit](#input\_allow\_merge\_commit) | Whether to allow merge commits on the repository (must be false to enforce linear trunk-based history). | `bool` | `false` | no |
| <a name="input_allow_rebase_merge"></a> [allow\_rebase\_merge](#input\_allow\_rebase\_merge) | Whether to allow rebase merge on the repository (must be false to enforce squash-merge policy). | `bool` | `false` | no |
| <a name="input_backup_secrets"></a> [backup\_secrets](#input\_backup\_secrets) | A map of sensitive secrets to inject into the 'backup' environment. | `map(string)` | `{}` | no |
| <a name="input_ci_secrets"></a> [ci\_secrets](#input\_ci\_secrets) | A map of sensitive secrets to inject into the 'ci' environment. | `map(string)` | `{}` | no |
| <a name="input_deploy_keys"></a> [deploy\_keys](#input\_deploy\_keys) | Deploy keys to register on the primary infra repository. | <pre>map(object({<br/>    title     = string<br/>    key       = string<br/>    read_only = bool<br/>  }))</pre> | <pre>{<br/>  "work-laptop": {<br/>    "key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhE5DoHICY85bnMIzXRGkggJ97ekZaJtzpQ6I7JgfF0 jmollner@liveperson.com",<br/>    "read_only": false,<br/>    "title": "work-laptop"<br/>  }<br/>}</pre> | no |
| <a name="input_enable_prevent_destroy"></a> [enable\_prevent\_destroy](#input\_enable\_prevent\_destroy) | Whether to prevent destruction of critical GitHub resources (defaults to true for production safety). | `bool` | `true` | no |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | The target GitHub organization or user account (overrides SOPS if provided). | `string` | `""` | no |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | Personal Access Token for GitHub authentication (overrides SOPS if provided). | `string` | `""` | no |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input\_secrets\_file\_path) | Path to the canonical SOPS credentials file holding github configuration (defaults to production credentials). | `string` | `"../../secrets/credentials.sops.yaml"` | no |
| <a name="input_sops_age_key_ci"></a> [sops\_age\_key\_ci](#input\_sops\_age\_key\_ci) | CI Age private key override for GitHub Actions environment secrets. | `string` | `""` | no |
| <a name="input_sops_age_key_file"></a> [sops\_age\_key\_file](#input\_sops\_age\_key\_file) | Path to the local Age keys file containing the CI private key. | `string` | `"~/.config/sops/age/keys.txt"` | no |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state and plan encryption. | `string` | `"homelab-state-encryption-passphrase-default"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deploy_keys"></a> [deploy\_keys](#output\_deploy\_keys) | Deploy keys registered on the infra repository. |
| <a name="output_repositories"></a> [repositories](#output\_repositories) | Map of managed GitHub repositories and their metadata. |
| <a name="output_repository_html_url"></a> [repository\_html\_url](#output\_repository\_html\_url) | The HTML URL of the primary infra GitHub repository. |
| <a name="output_repository_node_id"></a> [repository\_node\_id](#output\_repository\_node\_id) | The GraphQL Node ID of the primary infra GitHub repository. |
<!-- END_TF_DOCS -->
