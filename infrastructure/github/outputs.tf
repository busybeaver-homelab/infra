output "repository_html_url" {
  value       = data.github_repository.repo.html_url
  description = "The HTML URL of the managed GitHub repository."
  sensitive   = true
}

output "repository_node_id" {
  value       = data.github_repository.repo.node_id
  description = "The GraphQL Node ID of the managed GitHub repository."
  sensitive   = true
}
