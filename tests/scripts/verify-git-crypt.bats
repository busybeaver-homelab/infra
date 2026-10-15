#!/usr/bin/env bats
# Tests for scripts/verify-git-crypt.sh (R2-GATE-01)

load 'helpers/test_helper'

VERIFY_GIT_CRYPT="${REPO_ROOT}/scripts/verify-git-crypt.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "verify-git-crypt.sh succeeds on clean repository with --all" {
  cd "${REPO_ROOT}"
  run bash "${VERIFY_GIT_CRYPT}" --all
  [ "$status" -eq 0 ]
}

@test "verify-git-crypt.sh fails when filter=git-crypt file is staged in plaintext (R2-GATE-01)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/docs/plans"
  cp "${REPO_ROOT}/.gitattributes" "${mock_repo}/.gitattributes"
  cd "${mock_repo}"
  git init -q
  echo "# Plaintext plan leaked without git-crypt filter" > docs/plans/leaked-plan.md
  git add .gitattributes docs/plans/leaked-plan.md

  run bash "${VERIFY_GIT_CRYPT}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Plaintext or unencrypted blob detected in git-crypt path: docs/plans/leaked-plan.md" ]]
}

@test "verify-git-crypt.sh fails when backups or policy.hujson.tftpl is staged in plaintext" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/backups" "${mock_repo}/infrastructure/mesh"
  cp "${REPO_ROOT}/.gitattributes" "${mock_repo}/.gitattributes"
  cd "${mock_repo}"
  git init -q
  echo '{"secret": "plaintext"}' > backups/dump.json
  echo '{"acls": []}' > infrastructure/mesh/policy.hujson.tftpl
  git add .gitattributes backups/dump.json infrastructure/mesh/policy.hujson.tftpl

  run bash "${VERIFY_GIT_CRYPT}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "backups/dump.json" ]] || false
  [[ "$output" =~ "infrastructure/mesh/policy.hujson.tftpl" ]]
}

@test "verify-git-crypt.sh passes when filter=git-crypt files have GITCRYPT magic header and exempted files are plaintext" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/docs/plans" "${mock_repo}/infrastructure/mesh"
  cp "${REPO_ROOT}/.gitattributes" "${mock_repo}/.gitattributes"
  cd "${mock_repo}"
  git init -q
  printf '\0GITCRYPT\0encrypted-payload-bytes' > docs/plans/encrypted-plan.md
  printf '\0GITCRYPT\0encrypted-policy-bytes' > infrastructure/mesh/policy.hujson.tftpl
  echo '{"acls": ["ci-decoy"]}' > infrastructure/mesh/policy.ci.hujson.tftpl
  git add .gitattributes docs/plans/encrypted-plan.md infrastructure/mesh/policy.hujson.tftpl infrastructure/mesh/policy.ci.hujson.tftpl

  run bash "${VERIFY_GIT_CRYPT}" --all
  [ "$status" -eq 0 ]
}

@test "verify-git-crypt.sh fails closed when run outside a git repository" {
  local non_repo="${BATS_TMPDIR}/not-a-git-repo"
  mkdir -p "${non_repo}"
  cd "${non_repo}"
  GIT_DIR="${non_repo}/missing-git" run bash "${VERIFY_GIT_CRYPT}"
  [ "$status" -eq 2 ]
}
