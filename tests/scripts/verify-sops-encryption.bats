#!/usr/bin/env bats
# Tests for scripts/verify-sops-encryption.sh

load 'helpers/test_helper'

VERIFY_SCRIPT="${REPO_ROOT}/scripts/verify-sops-encryption.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "verify-sops-encryption.sh succeeds on valid repo secrets/credentials.ci.sops.yaml" {
  run bash "${VERIFY_SCRIPT}" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh skips .sops.yaml config file" {
  run bash "${VERIFY_SCRIPT}" "${REPO_ROOT}/.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh fails on non-canonical file path" {
  mkdir -p "${BATS_TMPDIR}/other"
  touch "${BATS_TMPDIR}/other/test.sops.yaml"
  run bash "${VERIFY_SCRIPT}" "${BATS_TMPDIR}/other/test.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Non-canonical" ]]
}

@test "verify-sops-encryption.sh fails on plaintext YAML with .sops.yaml extension" {
  # Setup temporary git repo simulating repo root with canonical path
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  echo "foo: bar" > "${mock_repo}/secrets/credentials.ci.sops.yaml"

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing or empty .sops.mac" ]]
}

@test "verify-sops-encryption.sh fails when sops: keyword is only in a comment or key name" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
# sops: metadata comment
sops_token: plaintext_value
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Missing or empty .sops.mac" ]]
}

@test "verify-sops-encryption.sh fails on partially encrypted YAML" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  cat <<'EOF' > "${mock_repo}/secrets/credentials.ci.sops.yaml"
encrypted_field: ENC[AES256_GCM,data:12345,iv:abc,tag:def,type:str]
plaintext_leak: dangerous_plain_value
sops:
  mac: ENC[AES256_GCM,data:mac123,iv:abc,tag:def,type:str]
  age:
    - age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v
EOF

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unencrypted scalar data found" ]]
}

@test "verify-sops-encryption.sh inspects staged blob: passes valid staged blob even if working copy is unencrypted" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cp "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" "${mock_repo}/secrets/credentials.ci.sops.yaml"
  cd "${mock_repo}"
  git init -q
  git add secrets/credentials.ci.sops.yaml
  # Now overwrite working tree with plaintext
  echo "unencrypted: true" > secrets/credentials.ci.sops.yaml

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "verify-sops-encryption.sh inspects staged blob: fails unencrypted staged blob even if working copy is encrypted" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/secrets"
  cd "${mock_repo}"
  git init -q
  echo "plaintext: leak" > secrets/credentials.ci.sops.yaml
  git add secrets/credentials.ci.sops.yaml
  # Now overwrite working tree with valid encrypted file
  cp "${REPO_ROOT}/secrets/credentials.ci.sops.yaml" "${mock_repo}/secrets/credentials.ci.sops.yaml"

  run bash "${VERIFY_SCRIPT}" "secrets/credentials.ci.sops.yaml"
  [ "$status" -ne 0 ]
}

@test ".sops.yaml contains secondary offline age recovery recipient for credentials.sops.yaml" {
  local age_recipients
  age_recipients=$(mise exec -- yq eval '.creation_rules[] | select(.path_regex == "^secrets/credentials\.sops\.ya?ml$") | .key_groups[].age // []' "${REPO_ROOT}/.sops.yaml")
  [ -n "$age_recipients" ]
  [[ "$age_recipients" =~ "age1" ]]
}
