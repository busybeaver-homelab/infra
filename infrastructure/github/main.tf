module "repository" {
  for_each = local.repositories
  source   = "./modules/repository"

  repository_name         = each.value.name
  description             = each.value.description
  visibility              = try(each.value.visibility, "public")
  topics                  = each.value.topics
  allow_merge_commit      = var.allow_merge_commit
  allow_rebase_merge      = var.allow_rebase_merge
  enable_prevent_destroy  = var.enable_prevent_destroy
  enable_merge_queue      = var.enable_merge_queue
  allowed_action_patterns = var.allowed_action_patterns
  ci_secrets              = local.ci_environment_secrets
  backup_secrets          = local.backup_environment_secrets
  ops_secrets             = local.ops_environment_secrets
  deploy_keys             = each.key == "infra" ? local.deploy_keys : {}
}

