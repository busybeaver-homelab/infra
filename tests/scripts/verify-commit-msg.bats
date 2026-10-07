#!/usr/bin/env bats
# Tests for scripts/verify-commit-msg.sh

load 'helpers/test_helper'

VERIFY_SCRIPT="${REPO_ROOT}/scripts/verify-commit-msg.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

# Helper to run verify script in a mock git repository with a specific branch
run_verify() {
  local branch="$1"
  local commit_msg="$2"
  local mock_repo="${BATS_TMPDIR}/mock-repo"

  rm -rf "${mock_repo}"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q -b "${branch}" 2>/dev/null || (git init -q && git checkout -q -b "${branch}")

  local msg_file="${mock_repo}/COMMIT_MSG"
  printf '%s\n' "${commit_msg}" > "${msg_file}"

  run bash "${VERIFY_SCRIPT}" "${msg_file}"
}

# --- Commit Message Format Tests ---

@test "verify-commit-msg.sh passes on valid standard conventional commit" {
  run_verify "feat/ci/add-gate" "feat(ci): add gate"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on conventional commit with breaking change indicator" {
  run_verify "feat/api/breaking-change" "fix(api)!: break backward compatibility"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on conventional commit without scope" {
  run_verify "fix/core/edge-case" "fix: handle edge case"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on conventional commit with complex scope" {
  run_verify "chore/deps/update" "chore(deps-dev): bump vitest from 1.0 to 2.0"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on commit message with trailing git comments" {
  local msg="docs(readme): update setup instructions

# Please enter the commit message for your changes. Lines starting
# with '#' will be ignored, and an empty message aborts the commit."
  run_verify "docs/readme/setup" "${msg}"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh fails on commit message without type prefix" {
  run_verify "feat/ci/add-gate" "just adding some stuff without type"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Conventional Commits" ]]
}

@test "verify-commit-msg.sh fails on uppercase type prefix" {
  run_verify "feat/ci/add-gate" "Feat(ci): uppercase type"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Conventional Commits" ]]
}

@test "verify-commit-msg.sh fails on missing colon separator" {
  run_verify "feat/ci/add-gate" "feat(ci) missing colon"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Conventional Commits" ]]
}

@test "verify-commit-msg.sh fails on invalid type keyword" {
  run_verify "feat/ci/add-gate" "custom(scope): unknown type keyword"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Conventional Commits" ]]
}

@test "verify-commit-msg.sh fails on empty commit message" {
  run_verify "feat/ci/add-gate" ""
  [ "$status" -ne 0 ]
}

# --- Branch Naming Tests ---

@test "verify-commit-msg.sh passes on valid branch name following <type>/<scope>/<short-desc>" {
  run_verify "feat/github/ruleset" "feat(github): configure ruleset"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on exempt branch 'main'" {
  run_verify "main" "chore(release): release v1.0.0"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on exempt branch 'master'" {
  run_verify "master" "chore(release): release v1.0.0"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh passes on detached HEAD" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  rm -rf "${mock_repo}"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "initial"
  git checkout -q --detach HEAD

  local msg_file="${mock_repo}/COMMIT_MSG"
  printf '%s\n' "feat(test): detached head commit" > "${msg_file}"

  run bash "${VERIFY_SCRIPT}" "${msg_file}"
  [ "$status" -eq 0 ]
}

@test "verify-commit-msg.sh fails on branch missing scope (only 2 segments)" {
  run_verify "feat/only-desc" "feat(test): missing scope in branch"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Branch name" ]]
}

@test "verify-commit-msg.sh fails on unstructured branch name" {
  run_verify "my-cool-feature" "feat(test): unstructured branch"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Branch name" ]]
}

@test "verify-commit-msg.sh fails on branch with invalid type prefix" {
  run_verify "random/scope/desc" "feat(test): invalid branch type"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Branch name" ]]
}

@test "verify-commit-msg.sh fails on branch with more than 3 segments" {
  run_verify "feat/scope/desc/extra" "feat(test): too many segments in branch"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Branch name" ]]
}

@test "verify-commit-msg.sh fails when commit message file argument is missing or unreadable" {
  run bash "${VERIFY_SCRIPT}" "${BATS_TMPDIR}/nonexistent-file"
  [ "$status" -ne 0 ]
}
