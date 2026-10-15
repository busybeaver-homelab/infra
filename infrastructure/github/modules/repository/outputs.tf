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

output "environments" {
  value = {
    ci           = github_repository_environment.ci.environment
    backup       = github_repository_environment.backup.environment
    code_quality = github_repository_environment.code_quality.environment
  }
  description = "Managed GitHub Actions environments."
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
}

output "actions_permissions" {
  value = {
    allowed_actions      = github_actions_repository_permissions.repo.allowed_actions
    sha_pinning_required = github_actions_repository_permissions.repo.sha_pinning_required
  }
  description = "Actions repository permissions."
}

output "visibility" {
  value       = github_repository.repo.visibility
  description = "The visibility of the managed repository."
}


