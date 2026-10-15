output "repositories" {
  value = {
    for k, mod in module.repository : k => {
      name          = mod.repository_name
      html_url      = mod.repository_html_url
      node_id       = mod.repository_node_id
      git_clone_url = mod.repository_git_clone_url
      ssh_clone_url = mod.repository_ssh_clone_url
    }
  }
  description = "Map of managed GitHub repositories and their metadata."
  sensitive   = true
}

output "repository_html_url" {
  value       = try(module.repository["infra"].repository_html_url, null)
  description = "The HTML URL of the primary infra GitHub repository."
  sensitive   = true
}

output "repository_node_id" {
  value       = try(module.repository["infra"].repository_node_id, null)
  description = "The GraphQL Node ID of the primary infra GitHub repository."
  sensitive   = true
}

output "deploy_keys" {
  value       = try(module.repository["infra"].deploy_keys, {})
  description = "Deploy keys registered on the infra repository."
  sensitive   = true
}

