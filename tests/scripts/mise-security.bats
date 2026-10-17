#!/usr/bin/env bats
# Tests for trivy security and misconfiguration scanning task

load 'helpers/test_helper'

@test "mise.toml specifies trivy in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^"aqua:aquasecurity/trivy"\s*=\s*"0\.75"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.toml defines check:security task with severity filters" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'tasks\."check:security"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'trivy fs .*--severity HIGH,CRITICAL' "$mise_config"
  [ "$status" -eq 0 ]
}
