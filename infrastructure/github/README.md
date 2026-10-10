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

> **Security:** Store the token as a SOPS-encrypted secret, never in plaintext.
> Load it via the `community.sops` vars plugin or inject it via the CI secrets mechanism.

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

| Name                                                                     | Version  |
| ------------------------------------------------------------------------ | -------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.8.0 |
| <a name="requirement_github"></a> [github](#requirement_github)          | ~> 6.0   |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                | ~> 1.1.1 |

## Providers

| Name                                                | Version |
| --------------------------------------------------- | ------- |
| <a name="provider_sops"></a> [sops](#provider_sops) | 1.1.1   |

## Modules

| Name                                                              | Source               | Version |
| ----------------------------------------------------------------- | -------------------- | ------- |
| <a name="module_repository"></a> [repository](#module_repository) | ./modules/repository | n/a     |

## Resources

| Name                                                                                                     | Type        |
| -------------------------------------------------------------------------------------------------------- | ----------- |
| [sops_file.secrets](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

| Name                                                                                                                 | Description                                                                                                    | Type          | Default                                         | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------- | ----------------------------------------------- | :------: |
| <a name="input_allow_merge_commit"></a> [allow\_merge\_commit](#input_allow_merge_commit)                            | Whether to allow merge commits on the repository (must be false to enforce linear trunk-based history).        | `bool`        | `false`                                         |    no    |
| <a name="input_allow_rebase_merge"></a> [allow\_rebase\_merge](#input_allow_rebase_merge)                            | Whether to allow rebase merge on the repository (must be false to enforce squash-merge policy).                | `bool`        | `false`                                         |    no    |
| <a name="input_backup_secrets"></a> [backup\_secrets](#input_backup_secrets)                                         | A map of sensitive secrets to inject into the 'backup' environment.                                            | `map(string)` | `{}`                                            |    no    |
| <a name="input_ci_secrets"></a> [ci\_secrets](#input_ci_secrets)                                                     | A map of sensitive secrets to inject into the 'ci' environment.                                                | `map(string)` | `{}`                                            |    no    |
| <a name="input_github_owner"></a> [github\_owner](#input_github_owner)                                               | The target GitHub organization or user account (overrides SOPS if provided).                                   | `string`      | `""`                                            |    no    |
| <a name="input_github_token"></a> [github\_token](#input_github_token)                                               | Personal Access Token for GitHub authentication (overrides SOPS if provided).                                  | `string`      | `""`                                            |    no    |
| <a name="input_secrets_file_path"></a> [secrets\_file\_path](#input_secrets_file_path)                               | Path to the canonical SOPS credentials file holding github configuration (defaults to production credentials). | `string`      | `"../../secrets/credentials.sops.yaml"`         |    no    |
| <a name="input_sops_age_key_ci"></a> [sops\_age\_key\_ci](#input_sops_age_key_ci)                                    | CI Age private key override for GitHub Actions environment secrets.                                            | `string`      | `""`                                            |    no    |
| <a name="input_sops_age_key_file"></a> [sops\_age\_key\_file](#input_sops_age_key_file)                              | Path to the local Age keys file containing the CI private key.                                                 | `string`      | `"~/.config/sops/age/keys.txt"`                 |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | Passphrase for OpenTofu state and plan encryption.                                                             | `string`      | `"homelab-state-encryption-passphrase-default"` |    no    |

## Outputs

| Name                                                                                           | Description                                                 |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| <a name="output_repositories"></a> [repositories](#output_repositories)                        | Map of managed GitHub repositories and their metadata.      |
| <a name="output_repository_html_url"></a> [repository\_html\_url](#output_repository_html_url) | The HTML URL of the primary infra GitHub repository.        |
| <a name="output_repository_node_id"></a> [repository\_node\_id](#output_repository_node_id)    | The GraphQL Node ID of the primary infra GitHub repository. |

<!-- END_TF_DOCS -->
