#!/usr/bin/env bats
# Tests for scripts/detect-private-keys.sh

load 'helpers/test_helper'

DETECT_SCRIPT="${REPO_ROOT}/scripts/detect-private-keys.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "detect-private-keys.sh passes on clean files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "public_key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..." > key.pub
  git add key.pub

  run bash "${DETECT_SCRIPT}" "key.pub"
  [ "$status" -eq 0 ]
}

@test "detect-private-keys.sh exempts scripts/detect-private-keys.sh itself" {
  run bash "${DETECT_SCRIPT}" "scripts/detect-private-keys.sh"
  [ "$status" -eq 0 ]
}

@test "detect-private-keys.sh detects staged Age secret key" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' 'AGE-SECRET-' 'KEY-REDACTED-LEAKED-AGE-KEY' > leaked.env
  git add leaked.env

  run bash "${DETECT_SCRIPT}" "leaked.env"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Age private key detected" ]]
}

@test "detect-private-keys.sh detects staged OpenSSH private key header" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' '-----BEGIN ' 'OPENSSH PRIVATE KEY-----' > id_ed25519
  git add id_ed25519

  run bash "${DETECT_SCRIPT}" "id_ed25519"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Private key header detected" ]]
}

@test "detect-private-keys.sh detects staged RSA/EC private key header" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' '-----BEGIN ' 'RSA PRIVATE KEY-----' > id_rsa
  git add id_rsa

  run bash "${DETECT_SCRIPT}" "id_rsa"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Private key header detected" ]]
}

@test "detect-private-keys.sh inspects staged blob: fails staged leak even if disk copy is sanitized" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '%s%s\n' 'AGE-SECRET-' 'KEY-REDACTED-LEAKED-AGE-KEY' > leaked.env
  git add leaked.env
  # Replace disk file with sanitized content
  echo "SAFE=true" > leaked.env

  run bash "${DETECT_SCRIPT}" "leaked.env"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Age private key detected" ]]
}

@test "detect-private-keys.sh inspects staged blob: passes clean staged blob even if disk copy contains key" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "SAFE=true" > file.env
  git add file.env
  # Place leak in disk copy only
  printf '%s%s\n' 'AGE-SECRET-' 'KEY-REDACTED-LEAKED-AGE-KEY' > file.env

  run bash "${DETECT_SCRIPT}" "file.env"
  [ "$status" -eq 0 ]
}
