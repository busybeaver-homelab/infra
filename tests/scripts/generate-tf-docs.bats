#!/usr/bin/env bats
# Tests for scripts/generate-tf-docs.sh

load 'helpers/test_helper'

GEN_DOCS_SCRIPT="${SCRIPTS_DIR}/generate-tf-docs.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "generate-tf-docs.sh exists and is executable" {
  [ -f "${GEN_DOCS_SCRIPT}" ]
  [ -x "${GEN_DOCS_SCRIPT}" ]
}

@test "generate-tf-docs.sh passes shellcheck" {
  run mise exec -- shellcheck "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh passes shfmt check" {
  run mise exec -- shfmt -d -i 2 -ci "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh runs cleanly on non-existent path" {
  run bash "${GEN_DOCS_SCRIPT}" "${BATS_TMPDIR}/nonexistent.tf"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh ignores non-infrastructure files" {
  local mock_other="${BATS_TMPDIR}/other_dir/main.tf"
  mkdir -p "$(dirname "$mock_other")"
  touch "$mock_other"

  run bash "${GEN_DOCS_SCRIPT}" "$mock_other"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh extracts directory name from an infrastructure file argument" {
  local mock_infra="${REPO_ROOT}/infrastructure/azure/main.tf"
  [ -f "$mock_infra" ] || skip "infrastructure/azure/main.tf does not exist"

  # Pass existing infrastructure file path
  run bash "${GEN_DOCS_SCRIPT}" "$mock_infra"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "infrastructure/azure" ]]
}
