#!/usr/bin/env bats
# Tests for actionlint GitHub Actions workflow validation

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "mise.toml specifies actionlint in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^"aqua:rhysd/actionlint"\s*=\s*"1\.7"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "lefthook.yml defines actionlint pre-commit hook on workflow files" {
  local lefthook_config="${REPO_ROOT}/lefthook.yml"
  [ -f "$lefthook_config" ]
  run grep -E "actionlint" "$lefthook_config"
  [ "$status" -eq 0 ]
  run grep -E '\.github/workflows/\*\.\{yml,yaml\}' "$lefthook_config"
  [ "$status" -eq 0 ]
}

@test "actionlint validates all existing repository GitHub Actions workflows successfully" {
  run mise exec -- actionlint "${REPO_ROOT}/.github/workflows/"*.yml
  [ "$status" -eq 0 ]
}
