locals {
  # GitHub Free org plans support merge queues only on public repositories.
  enable_merge_queue = coalesce(var.enable_merge_queue, var.visibility == "public")

  # Refs allowed to deploy to the synthetic-only `ci` environment (STD-CI-23), matched
  # against GITHUB_REF: push/schedule on main, pull_request runs, and merge queue groups.
  # `protected_branches = true` is not usable here: the repository protects `main` with a
  # ruleset, not classic branch protection, and GitHub then lets every branch deploy.
  ci_deployment_branch_patterns = toset(concat(
    ["main", "refs/pull/*/merge"],
    local.enable_merge_queue ? ["gh-readonly-queue/main/*"] : [],
  ))

  # SARIF code-scanning tools that report on every pull request via `.github/workflows/codeql.yml`
  # (`gh api repos/<owner>/<repo>/code-scanning/analyses --jq '[.[].tool.name] | unique'`, R2-CI-07 / STD-CI-59).
  required_code_scanning_tools = toset([
    "CodeQL",
    "Trivy",
    "checkov",
    "shellcheck",
    "zizmor",
  ])
}
