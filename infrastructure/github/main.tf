module "repository" {
  for_each = local.repositories
  source   = "./modules/repository"

  repository_name    = each.value.name
  description        = each.value.description
  topics             = each.value.topics
  allow_merge_commit = var.allow_merge_commit
  allow_rebase_merge = var.allow_rebase_merge
  ci_secrets         = local.ci_environment_secrets
  backup_secrets     = local.backup_environment_secrets
}
