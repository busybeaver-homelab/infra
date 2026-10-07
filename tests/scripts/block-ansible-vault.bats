#!/usr/bin/env bats
# Tests for scripts/block-ansible-vault.sh

load 'helpers/test_helper'

BLOCK_SCRIPT="${REPO_ROOT}/scripts/block-ansible-vault.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "block-ansible-vault.sh passes on clean files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "key: value" > clean.yaml
  git add clean.yaml

  run bash "${BLOCK_SCRIPT}" "clean.yaml"
  [ "$status" -eq 0 ]
}

@test "block-ansible-vault.sh exempts scripts/block-ansible-vault.sh itself by exact path match" {
  run bash "${BLOCK_SCRIPT}" "scripts/block-ansible-vault.sh"
  [ "$status" -eq 0 ]
}

@test "block-ansible-vault.sh blocks staged file containing ansible vault header" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > vault.yaml
  git add vault.yaml

  run bash "${BLOCK_SCRIPT}" "vault.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh blocks bypass attempt via evil-block-ansible-vault.sh" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > evil-block-ansible-vault.sh
  git add evil-block-ansible-vault.sh

  run bash "${BLOCK_SCRIPT}" "evil-block-ansible-vault.sh"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh inspects staged blob: fails unencrypted staged blob even if disk copy is cleaned" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > secret.yaml
  git add secret.yaml
  # Replace disk file with clean content
  echo "clean: true" > secret.yaml

  run bash "${BLOCK_SCRIPT}" "secret.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh inspects staged blob: passes clean staged blob even if disk copy has vault token" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "clean: true" > secret.yaml
  git add secret.yaml
  # Place vault token in disk file only (unstaged)
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > secret.yaml

  run bash "${BLOCK_SCRIPT}" "secret.yaml"
  [ "$status" -eq 0 ]
}
