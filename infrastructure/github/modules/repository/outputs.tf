output "repository_name" {
  value       = github_repository.repo.name
  description = "The name of the managed GitHub repository."
  sensitive   = true
}

output "repository_html_url" {
  value       = github_repository.repo.html_url
  description = "The HTML URL of the managed GitHub repository."
  sensitive   = true
}

output "repository_node_id" {
  value       = github_repository.repo.node_id
  description = "The GraphQL Node ID of the managed GitHub repository."
  sensitive   = true
}

output "repository_git_clone_url" {
  value       = github_repository.repo.git_clone_url
  description = "The URL that can be provided to git clone over HTTPS."
  sensitive   = true
}

output "repository_ssh_clone_url" {
  value       = github_repository.repo.ssh_clone_url
  description = "The URL that can be provided to git clone over SSH."
  sensitive   = true
}

output "allow_squash_merge" {
  value       = github_repository.repo.allow_squash_merge
  description = "Whether squash merge is enabled."
}

output "allow_merge_commit" {
  value       = github_repository.repo.allow_merge_commit
  description = "Whether merge commits are enabled."
}

output "allow_rebase_merge" {
  value       = github_repository.repo.allow_rebase_merge
  description = "Whether rebase merge is enabled."
}

output "delete_branch_on_merge" {
  value       = github_repository.repo.delete_branch_on_merge
  description = "Whether head branches are automatically deleted upon merge."
}

output "ruleset_enforcement" {
  value       = github_repository_ruleset.main_protection.enforcement
  description = "Enforcement level of the main branch ruleset."
}

output "merge_queue_enabled" {
  value       = length(github_repository_ruleset.main_protection.rules[0].merge_queue) > 0
  description = "Whether GitHub Merge Queue is enabled on the main branch ruleset."
}

output "ruleset_required_checks" {
  value       = github_repository_ruleset.main_protection.rules[0].required_status_checks[0].required_check
  description = "Required status checks configured on the main branch ruleset."
}

output "ruleset_required_code_scanning_tools" {
  value       = github_repository_ruleset.main_protection.rules[0].required_code_scanning[0].required_code_scanning_tool
  description = "Required code scanning tools configured on the main branch ruleset."
}

output "ruleset_bypass_actors" {
  value       = github_repository_ruleset.main_protection.bypass_actors
  description = "Bypass actors configured on the main branch ruleset."
}

output "ruleset_required_linear_history" {
  value       = github_repository_ruleset.main_protection.rules[0].required_linear_history
  description = "Whether linear history is required on the main branch ruleset."
}

output "ci_deployment_branch_patterns" {
  value       = sort([for policy in github_repository_environment_deployment_policy.ci : policy.branch_pattern])
  description = "Ref patterns allowed to deploy to the synthetic-only 'ci' environment."
}

output "environments" {
  value = {
    ci           = github_repository_environment.ci.environment
    backup       = github_repository_environment.backup.environment
    ops          = github_repository_environment.ops.environment
    code_quality = github_repository_environment.code_quality.environment
  }
  description = "Managed GitHub Actions environments."
}

output "ops_environment_name" {
  value       = github_repository_environment.ops.environment
  description = "The name of the ops GitHub Actions environment."
}

output "backup_deployment_branch_pattern" {
  value       = github_repository_environment_deployment_policy.backup_main.branch_pattern
  description = "Branch pattern allowed to deploy to the 'backup' environment."
}

output "ops_deployment_branch_pattern" {
  value       = github_repository_environment_deployment_policy.ops_main.branch_pattern
  description = "Branch pattern allowed to deploy to the 'ops' environment."
}

output "deploy_keys" {
  value = {
    for k, v in github_repository_deploy_key.deploy_keys : k => {
      id        = v.id
      title     = v.title
      read_only = v.read_only
    }
  }
  description = "Managed deploy keys."
  sensitive   = true
}

output "actions_permissions" {
  value = {
    allowed_actions         = github_actions_repository_permissions.repo.allowed_actions
    sha_pinning_required    = github_actions_repository_permissions.repo.sha_pinning_required
    allowed_action_patterns = var.allowed_action_patterns
    # Configured at the organization level (see main.tf comment on github_actions_repository_permissions.repo):
    # github_owned_allowed = github_actions_repository_permissions.repo.allowed_actions_config[0].github_owned_allowed
    # verified_allowed     = github_actions_repository_permissions.repo.allowed_actions_config[0].verified_allowed
    # patterns_allowed     = tolist(github_actions_repository_permissions.repo.allowed_actions_config[0].patterns_allowed)
  }
  description = "Actions repository permissions."
}

output "visibility" {
  value       = github_repository.repo.visibility
  description = "The visibility of the managed repository."
}

output "has_issues" {
  value       = github_repository.repo.has_issues
  description = "Whether GitHub Issues are enabled on the repository (required for Renovate Dependency Dashboard)."
}

output "dependabot_security_updates_enabled" {
  value       = github_repository_dependabot_security_updates.repo.enabled
  description = "Whether Dependabot automated security update PRs are enabled (disabled in favor of Renovate)."
}
