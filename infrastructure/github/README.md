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

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_github"></a> [github](#provider\_github) | 6.12.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [github_actions_environment_secret.ci_secrets](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_environment_secret) | resource |
| [github_repository.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_environment.ci](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_environment.production](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_environment) | resource |
| [github_repository_ruleset.main_protection](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset) | resource |
| [github_repository_vulnerability_alerts.repo](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_vulnerability_alerts) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ci_secrets"></a> [ci\_secrets](#input\_ci\_secrets) | A map of sensitive secrets to inject into the 'ci' environment. | `map(string)` | `{}` | no |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | The target GitHub organization or user account. | `string` | n/a | yes |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | Personal Access Token for GitHub authentication. | `string` | n/a | yes |
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | The name of the target GitHub repository. | `string` | `"homelab-infra"` | no |
| <a name="input_reviewers_for_production"></a> [reviewers\_for\_production](#input\_reviewers\_for\_production) | List of GitHub user or team IDs that can approve production deployments. | `list(string)` | `[]` | no |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input\_state\_encryption\_passphrase) | Passphrase for OpenTofu state encryption (AES-GCM via PBKDF2). Never hardcode — inject via TF\_VAR\_state\_encryption\_passphrase environment variable. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_html_url"></a> [repository\_html\_url](#output\_repository\_html\_url) | The HTML URL of the managed GitHub repository. |
| <a name="output_repository_node_id"></a> [repository\_node\_id](#output\_repository\_node\_id) | The GraphQL Node ID of the managed GitHub repository. |
<!-- END_TF_DOCS -->
