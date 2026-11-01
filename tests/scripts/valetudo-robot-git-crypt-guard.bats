#!/usr/bin/env bats
# Tests for configuration/roles/valetudo_robot/files/assert-git-crypt-target.sh
# (refuses to write calibration data unless the target is git-crypt protected
# in an unlocked checkout). Throwaway git repos only; no real git-crypt key.

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/configuration/roles/valetudo_robot/files/assert-git-crypt-target.sh"
TARGET='backups/robots/x40-ultra/x40-ultra-20261031T000000Z.tar'

setup() {
  setup_tmpdir
  REPO="${BATS_TMPDIR}/repo"
  git init -q -b main "${REPO}"
  git -C "${REPO}" config user.email 'test@example.com'
  git -C "${REPO}" config user.name 'Guard Test'
  git -C "${REPO}" config commit.gpgsign false
}

teardown() {
  teardown_tmpdir
}

add_git_crypt_attribute() {
  printf 'backups/** filter=git-crypt diff=git-crypt\n' >"${REPO}/.gitattributes"
  git -C "${REPO}" add .gitattributes
  git -C "${REPO}" commit -q -m 'attrs'
}

add_key_file() {
  mkdir -p "${REPO}/.git/git-crypt/keys"
  printf 'synthetic\n' >"${REPO}/.git/git-crypt/keys/default"
}

configure_filter() {
  git -C "${REPO}" config filter.git-crypt.clean '"git-crypt" clean'
  git -C "${REPO}" config filter.git-crypt.smudge '"git-crypt" smudge'
}

unlock_repo() {
  add_key_file
  configure_filter
}

expected_message() {
  printf 'ERROR: %s is not git-crypt protected or the repository is locked; refusing to write calibration data' "$1"
}

@test "unlocked repo with the git-crypt attribute passes" {
  add_git_crypt_attribute
  unlock_repo
  run "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "target without the git-crypt attribute is refused" {
  add_git_crypt_attribute
  unlock_repo
  run --separate-stderr "${SCRIPT}" "${REPO}" 'plain/x40-ultra.tar'
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message 'plain/x40-ultra.tar')" ]
}

@test "repo without any attributes is refused" {
  git -C "${REPO}" commit -q --allow-empty -m 'init'
  unlock_repo
  run --separate-stderr "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message "${TARGET}")" ]
}

@test "locked repo (attribute but no git-crypt/keys dir) is refused" {
  add_git_crypt_attribute
  run --separate-stderr "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message "${TARGET}")" ]
}

@test "locked repo with an empty git-crypt/keys dir is refused" {
  add_git_crypt_attribute
  mkdir -p "${REPO}/.git/git-crypt/keys"
  run "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
}

@test "key present but git-crypt filter not configured is refused" {
  add_git_crypt_attribute
  add_key_file
  run --separate-stderr "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message "${TARGET}")" ]
}

@test "symlinked target directory escaping the repository is refused" {
  add_git_crypt_attribute
  unlock_repo
  mkdir -p "${BATS_TMPDIR}/outside/x40-ultra" "${REPO}/backups"
  ln -s "${BATS_TMPDIR}/outside" "${REPO}/backups/robots"
  run --separate-stderr "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message "${TARGET}")" ]
}

@test "symlinked target file is refused" {
  add_git_crypt_attribute
  unlock_repo
  mkdir -p "${REPO}/backups/robots/x40-ultra"
  ln -s "${BATS_TMPDIR}/elsewhere.tar" "${REPO}/${TARGET}"
  run "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 1 ]
}

@test "existing real target directories pass" {
  add_git_crypt_attribute
  unlock_repo
  mkdir -p "${REPO}/backups/robots/x40-ultra"
  run "${SCRIPT}" "${REPO}" "${TARGET}"
  [ "${status}" -eq 0 ]
}

@test "worktree without the git-crypt symlink is refused" {
  add_git_crypt_attribute
  unlock_repo
  git -C "${REPO}" worktree add -q --no-track -b wt-test "${BATS_TMPDIR}/wt" main
  run --separate-stderr "${SCRIPT}" "${BATS_TMPDIR}/wt" "${TARGET}"
  [ "${status}" -eq 1 ]
  [ "${stderr}" = "$(expected_message "${TARGET}")" ]
}

@test "worktree with the git-crypt symlink passes" {
  add_git_crypt_attribute
  unlock_repo
  git -C "${REPO}" worktree add -q --no-track -b wt-test "${BATS_TMPDIR}/wt" main
  wt_git_dir="$(git -C "${BATS_TMPDIR}/wt" rev-parse --absolute-git-dir)"
  ln -s ../../git-crypt "${wt_git_dir}/git-crypt"
  run "${SCRIPT}" "${BATS_TMPDIR}/wt" "${TARGET}"
  [ "${status}" -eq 0 ]
}

@test "relative repo root is resolved correctly" {
  add_git_crypt_attribute
  unlock_repo
  cd "${BATS_TMPDIR}"
  run "${SCRIPT}" repo "${TARGET}"
  [ "${status}" -eq 0 ]
}

@test "target escaping the repository is refused" {
  add_git_crypt_attribute
  unlock_repo
  run "${SCRIPT}" "${REPO}" "backups/../../outside.tar"
  [ "${status}" -eq 1 ]
  run "${SCRIPT}" "${REPO}" "/tmp/x40-ultra.tar"
  [ "${status}" -eq 1 ]
}

@test "non-repository root is refused" {
  mkdir -p "${BATS_TMPDIR}/not-a-repo"
  run "${SCRIPT}" "${BATS_TMPDIR}/not-a-repo" "${TARGET}"
  [ "${status}" -eq 1 ]
}

@test "wrong argument count gives exit 2" {
  run "${SCRIPT}" "${REPO}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"usage"* ]] || false
}
