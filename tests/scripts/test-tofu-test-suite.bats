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
