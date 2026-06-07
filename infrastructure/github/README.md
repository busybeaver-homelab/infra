# GitHub Repository Management (OpenTofu)

This module manages the GitHub repository settings and branch protection rules
for this repo as code via the `integrations/github` Terraform provider.

## Required GitHub Token Scopes

The `github_token` variable must be a GitHub Personal Access Token (classic) or
a GitHub App installation token with **all** of the following scopes:

| Scope | Reason |
|-------|--------|
| `repo` | Read/write repository settings |
| `admin:repo_hook` | Manage webhooks |
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

| Name | Description |
|------|-------------|
| `github_token` | PAT or App token with repo + admin scopes |
| `github_owner` | GitHub org or username owning this repo |
| `repository_name` | Repository name (default: `homelab-infra`) |
