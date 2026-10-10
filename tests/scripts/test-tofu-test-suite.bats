#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "infrastructure/tests Go terratest files are removed" {
  [ ! -f "$REPO_ROOT/infrastructure/tests/go.mod" ]
  [ ! -f "$REPO_ROOT/infrastructure/tests/go.sum" ]
  run find "$REPO_ROOT/infrastructure/tests" -name "*.go"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "all 7 infrastructure modules define native .tftest.hcl test suites" {
  [ -f "$REPO_ROOT/infrastructure/oci/tests/oci.tftest.hcl" ] || [ -f "$REPO_ROOT/infrastructure/oci/tests/backup.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/cloudflare/tests/cloudflare.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/gcp/tests/gcp.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/azure/tests/azure.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/github/tests/github.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/homelab/tests/homelab.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/monitoring/tests/monitoring.tftest.hcl" ]
}

@test "mise.toml configures test:infra using native tofu test" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  run grep -E "tasks\.\"test:infra\"" "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E "tofu test" "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.toml test:infra executes module tests concurrently" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  local task_def
  task_def=$(sed -n '/\[tasks\."test:infra"\]/,/\[settings\]/p' "$mise_config")
  run grep -E "wait|tmp_dir|pids" <<<"$task_def"
  [ "$status" -eq 0 ]
}

@test "all 7 infrastructure modules define negative.tftest.hcl test suites" {
  [ -f "$REPO_ROOT/infrastructure/oci/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/cloudflare/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/github/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/monitoring/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/gcp/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/azure/tests/negative.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/homelab/tests/negative.tftest.hcl" ]
}

@test "mise.toml defines test:all and test:molecule tasks" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'tasks\."test:all"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:molecule"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "infrastructure/oci defines native invariant check blocks for always-free shape and project tagging" {
  local checks_file="$REPO_ROOT/infrastructure/oci/checks.tf"
  [ -f "$checks_file" ]
  run grep -E 'check "enforce_always_free_shape_compliance"' "$checks_file"
  [ "$status" -eq 0 ]
  run grep -E 'check "enforce_mandatory_project_tag"' "$checks_file"
  [ "$status" -eq 0 ]
}

@test "isolated child modules define native unit .tftest.hcl test suites" {
  [ -f "$REPO_ROOT/infrastructure/cloudflare/modules/zone/tests/zone.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/github/modules/repository/tests/repository.tftest.hcl" ]
}

@test "all 7 infrastructure modules define native checks.tf invariant policy checks" {
  local modules=(oci cloudflare gcp azure github homelab monitoring)
  for mod in "${modules[@]}"; do
    [ -f "$REPO_ROOT/infrastructure/$mod/checks.tf" ]
    run grep -E '^check ' "$REPO_ROOT/infrastructure/$mod/checks.tf"
    [ "$status" -eq 0 ]
  done
}

@test "mutation.tftest.hcl lifecycle mutation test suites exist in cloudflare, gcp, github, and oci" {
  [ -f "$REPO_ROOT/infrastructure/cloudflare/tests/mutation.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/gcp/tests/mutation.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/github/tests/mutation.tftest.hcl" ]
  [ -f "$REPO_ROOT/infrastructure/oci/tests/mutation.tftest.hcl" ]
}

@test "mise.toml configures test:tofu:children, test:tofu:mutations, test:tofu:checks, and test:inventory:matrix" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'tasks\."test:tofu:children"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:tofu:mutations"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:tofu:checks"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:inventory:matrix"' "$mise_config"
  [ "$status" -eq 0 ]
}


