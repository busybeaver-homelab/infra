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

@test "block-ansible-vault.sh executes batched scan on multiple clean files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  for i in $(seq 1 20); do
    echo "clean content $i" > "file_$i.yaml"
  done
  git add file_*.yaml

  run bash "${BLOCK_SCRIPT}" file_*.yaml
  [ "$status" -eq 0 ]
}

@test "block-ansible-vault.sh detects multiple vault files in a batched scan" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "clean content" > file_clean.yaml
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > vault1.yaml
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > vault2.yaml
  git add file_clean.yaml vault1.yaml vault2.yaml

  run bash "${BLOCK_SCRIPT}" file_clean.yaml vault1.yaml vault2.yaml
  [ "$status" -ne 0 ]
  [[ "$output" =~ "vault1.yaml" ]] || false
  [[ "$output" =~ "vault2.yaml" ]] || false
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh blocks vault header in staged file containing NUL byte (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf 'prefix\0byte\n%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > nul_vault.bin
  git add nul_vault.bin

  run bash "${BLOCK_SCRIPT}" "nul_vault.bin"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh blocks vault header in staged file marked -diff in .gitattributes (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "*.nodiff -diff" > .gitattributes
  printf '%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > vault.nodiff
  git add .gitattributes vault.nodiff

  run bash "${BLOCK_SCRIPT}" "vault.nodiff"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Ansible Vault file detected" ]]
}

@test "block-ansible-vault.sh skips git-crypt encrypted staged blobs cleanly (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '\0GITCRYPT\0%s%s\n' '$ANSIBLE' '_VAULT;1.1;AES256' > encrypted_vault.md
  git add encrypted_vault.md

  run bash "${BLOCK_SCRIPT}" "encrypted_vault.md"
  [ "$status" -eq 0 ]
}

@test "block-ansible-vault.sh fails closed with exit 2 on broken GIT_DIR or invalid pathspec (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"

  GIT_DIR="${mock_repo}/broken-git-dir" run bash "${BLOCK_SCRIPT}"
  [ "$status" -eq 2 ]

  git init -q
  run bash "${BLOCK_SCRIPT}" ":(invalid-magic)foo"
  [ "$status" -eq 2 ]
}
