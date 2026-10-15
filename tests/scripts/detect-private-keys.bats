#!/usr/bin/env bats
# Tests for scripts/detect-private-keys.sh

load 'helpers/test_helper'

DETECT_SCRIPT="${REPO_ROOT}/scripts/detect-private-keys.sh"

setup() {
  setup_tmpdir
  # Format-valid (matches the detector) but not a real identity: built at runtime so no
  # key-shaped literal is ever committed. Never use real or previously leaked keys.
  FAKE_AGE_KEY="AGE-SECRET-KEY-1$(printf 'Q%.0s' $(seq 1 58))"
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
  printf '%s
' "${FAKE_AGE_KEY}" > leaked.env
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
  printf '%s
' "${FAKE_AGE_KEY}" > leaked.env
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
  printf '%s
' "${FAKE_AGE_KEY}" > file.env

  run bash "${DETECT_SCRIPT}" "file.env"
  [ "$status" -eq 0 ]
}

@test "detect-private-keys.sh executes batched scan on multiple clean files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  for i in $(seq 1 20); do
    echo "clean content $i" > "file_$i.txt"
  done
  git add file_*.txt

  run bash "${DETECT_SCRIPT}" file_*.txt
  [ "$status" -eq 0 ]
}

@test "detect-private-keys.sh detects multiple leaks in a batched scan" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "clean content" > file_clean.txt
  printf '%s
' "${FAKE_AGE_KEY}" > file_age.env
  printf '%s%s\n' '-----BEGIN ' 'OPENSSH PRIVATE KEY-----' > file_ssh.key
  git add file_clean.txt file_age.env file_ssh.key

  run bash "${DETECT_SCRIPT}" file_clean.txt file_age.env file_ssh.key
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Age private key detected in file_age.env" ]] || false
  [[ "$output" =~ "Private key header detected in file_ssh.key" ]]
}

@test "detect-private-keys.sh does not exempt its own test suite" {
  run grep -F 'tests/scripts/detect-private-keys.bats' "${REPO_ROOT}/scripts/detect-private-keys.sh"
  [ "$status" -eq 1 ]
}

@test "detector test suite contains no key-shaped literal" {
  run grep -E "AGE-SECRET-'? *'?KEY-1[0-9A-Z]{10}" "${REPO_ROOT}/tests/scripts/detect-private-keys.bats"
  [ "$status" -eq 1 ]
}

@test "detect-private-keys.sh detects private key in staged file containing NUL byte (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf 'binary\0prefix\n%s%s\n' '-----BEGIN ' 'RSA PRIVATE KEY-----' > nul_key.bin
  git add nul_key.bin

  run bash "${DETECT_SCRIPT}" "nul_key.bin"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Private key header detected in nul_key.bin" ]]
}

@test "detect-private-keys.sh detects private key in staged file marked -diff in .gitattributes (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "*.nodiff -diff" > .gitattributes
  printf '%s%s\n' '-----BEGIN ' 'EC PRIVATE KEY-----' > secret.nodiff
  git add .gitattributes secret.nodiff

  run bash "${DETECT_SCRIPT}" "secret.nodiff"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Private key header detected in secret.nodiff" ]]
}

@test "detect-private-keys.sh rejects staged binary key containers (.p12, .jks, .kdbx) and DER 30 82 magic bytes (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "dummy-pkcs12" > cert.p12
  printf '\x30\x82\x01\x22\x02\x01\x00' > raw_der.key
  git add cert.p12 raw_der.key

  run bash "${DETECT_SCRIPT}" cert.p12 raw_der.key
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Binary key container (cert.p12) is forbidden" ]] || false
  [[ "$output" =~ "DER-encoded binary key/container detected in raw_der.key" ]]
}

@test "detect-private-keys.sh skips git-crypt encrypted staged blobs cleanly (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  printf '\0GITCRYPT\0%s%s\n' '-----BEGIN ' 'RSA PRIVATE KEY-----' > encrypted.md
  git add encrypted.md

  run bash "${DETECT_SCRIPT}" encrypted.md
  [ "$status" -eq 0 ]
}

@test "detect-private-keys.sh fails closed with exit 2 on broken GIT_DIR or invalid pathspec (R2-GATE-03)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"

  GIT_DIR="${mock_repo}/broken-git-dir" run bash "${DETECT_SCRIPT}"
  [ "$status" -eq 2 ]

  git init -q
  run bash "${DETECT_SCRIPT}" ":(invalid-magic)foo"
  [ "$status" -eq 2 ]
}

