#!/usr/bin/env bats
# Tests for scripts/check-sops-secret-leaks.sh

load 'helpers/test_helper'

LEAK_SCRIPT="${REPO_ROOT}/scripts/check-sops-secret-leaks.sh"

assert_output_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: ${expected}" >&2
    echo "Actual output: ${output}" >&2
    return 1
  fi
}

assert_output_not_contains() {
  local unexpected="$1"
  if [[ "$output" == *"$unexpected"* ]]; then
    echo "Expected output NOT to contain sensitive value" >&2
    return 1
  fi
}

setup_file() {
  export SHARED_DIR="${BATS_FILE_TMPDIR}/shared"
  mkdir -p "${SHARED_DIR}/secrets"

  export TEST_AGE_KEY_FILE="${SHARED_DIR}/age-key.txt"
  age-keygen -o "${TEST_AGE_KEY_FILE}" 2>/dev/null
  local age_pub
  age_pub=$(grep -E '^# public key: ' "${TEST_AGE_KEY_FILE}" | sed 's/^# public key: //')
  export TEST_AGE_PUB="${age_pub}"

  cat <<EOF >"${SHARED_DIR}/.sops.yaml"
creation_rules:
  - path_regex: ^secrets/credentials(\.ci|\.ci\.colliding)?\.sops\.yaml$
    age: >-
      ${age_pub}
EOF

  # Construct synthetic secret fragments dynamically so this test file stays clean
  local age_sec_prefix="AGE-SECRET-KEY-1"
  local age_sec_body="QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ"
  local hdr_begin="-----BEGIN"
  local hdr_end="-----END"
  local hdr_type=" OPENSSH PRIVATE KEY-----"

  export PROD_TOKEN_VAL="prod-super-secret-api-token-998877"
  export CI_TOKEN_VAL="ci-decoy-synthetic-api-token-112233"
  export PROD_AGE_BODY="${age_sec_body}"
  export PROD_AGE_BODY_LOWER="qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
  export PROD_PEM_LINE="SYNTHETIC_PEM_BODY_LINE_ALPHA_9876543210_OMEGA_KEYMATERIAL"

  cat <<EOF >"${SHARED_DIR}/secrets/credentials.sops.yaml"
is_production: true
gcp:
  project_id: "prod-homelab-project-42"
  region: "us-central1"
cloudflare:
  api_token: "${PROD_TOKEN_VAL}"
  config:
    zones:
      primary:
        dns_records:
          a_1:
            type: "A"
            content: "198.51.100.42"
sops_age_key: "${age_sec_prefix}${age_sec_body}"
ssh_priv_key: |
  ${hdr_begin}${hdr_type}
  ${PROD_PEM_LINE}
  ${hdr_end}${hdr_type}
EOF

  cat <<EOF >"${SHARED_DIR}/secrets/credentials.ci.sops.yaml"
is_production: false
gcp:
  project_id: "ci-decoy-project-99"
  region: "us-central1"
cloudflare:
  api_token: "${CI_TOKEN_VAL}"
  config:
    zones:
      primary:
        dns_records:
          a_1:
            type: "A"
            content: "192.0.2.10"
sops_age_key: "${age_sec_prefix}ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
ssh_priv_key: |
  ${hdr_begin}${hdr_type}
  CI_DECOY_PEM_BODY_LINE_BETA_1234567890_OMEGA_KEYMATERIAL00
  ${hdr_end}${hdr_type}
EOF

  # Pre-build a colliding CI SOPS fixture that duplicates prod's cloudflare.api_token
  cat <<EOF >"${SHARED_DIR}/secrets/credentials.ci.colliding.sops.yaml"
is_production: false
gcp:
  project_id: "ci-decoy-project-99"
  region: "us-central1"
cloudflare:
  api_token: "${PROD_TOKEN_VAL}"
  config:
    zones:
      primary:
        dns_records:
          a_1:
            type: "A"
            content: "192.0.2.10"
sops_age_key: "${age_sec_prefix}ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
ssh_priv_key: |
  ${hdr_begin}${hdr_type}
  CI_DECOY_PEM_BODY_LINE_BETA_1234567890_OMEGA_KEYMATERIAL00
  ${hdr_end}${hdr_type}
EOF

  (
    cd "${SHARED_DIR}"
    SOPS_AGE_KEY_FILE="${TEST_AGE_KEY_FILE}" sops --encrypt --in-place secrets/credentials.sops.yaml
    SOPS_AGE_KEY_FILE="${TEST_AGE_KEY_FILE}" sops --encrypt --in-place secrets/credentials.ci.sops.yaml
    SOPS_AGE_KEY_FILE="${TEST_AGE_KEY_FILE}" sops --encrypt --in-place secrets/credentials.ci.colliding.sops.yaml
  )
}

setup() {
  setup_tmpdir
  export MOCK_REPO="${BATS_TMPDIR}/repo"
  mkdir -p "${MOCK_REPO}/secrets"
  cp "${SHARED_DIR}/.sops.yaml" "${MOCK_REPO}/.sops.yaml"
  cp "${SHARED_DIR}/secrets/credentials.sops.yaml" "${MOCK_REPO}/secrets/credentials.sops.yaml"
  cp "${SHARED_DIR}/secrets/credentials.ci.sops.yaml" "${MOCK_REPO}/secrets/credentials.ci.sops.yaml"
  export SOPS_AGE_KEY_FILE="${TEST_AGE_KEY_FILE}"
  unset SOPS_AGE_KEY
  unset CI
}

teardown() {
  teardown_tmpdir
}

@test "check-sops-secret-leaks.sh passes on clean staged files and disjoint SOPS files" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' >clean_test.bats
@test "sample test" {
  local token="completely-synthetic-test-only-value"
  [ -n "$token" ]
}
EOF
  git add clean_test.bats

  run bash "${LEAK_SCRIPT}" --check-files clean_test.bats
  [ "$status" -eq 0 ]

  run bash "${LEAK_SCRIPT}" --check-disjointness
  [ "$status" -eq 0 ]
}

@test "check-sops-secret-leaks.sh detects exact production SOPS secret in a .bats test without printing secret" {
  cd "${MOCK_REPO}"
  git init -q
  mkdir -p tests/scripts
  cat <<EOF >tests/scripts/leaked.bats
@test "leaked prod token" {
  export CF_TOKEN="${PROD_TOKEN_VAL}"
}
EOF
  git add tests/scripts/leaked.bats

  run bash "${LEAK_SCRIPT}" --check-files tests/scripts/leaked.bats
  [ "$status" -eq 1 ]
  assert_output_contains "tests/scripts/leaked.bats:2"
  assert_output_contains "secrets/credentials.sops.yaml:cloudflare.api_token"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh detects CI SOPS secret in a .tftest.hcl file without printing secret" {
  cd "${MOCK_REPO}"
  git init -q
  mkdir -p infrastructure/cloudflare/tests
  cat <<EOF >infrastructure/cloudflare/tests/unit.tftest.hcl
variables {
  api_token = "${CI_TOKEN_VAL}"
}
EOF
  git add infrastructure/cloudflare/tests/unit.tftest.hcl

  run bash "${LEAK_SCRIPT}" --check-files infrastructure/cloudflare/tests/unit.tftest.hcl
  [ "$status" -eq 1 ]
  assert_output_contains "infrastructure/cloudflare/tests/unit.tftest.hcl:2"
  assert_output_contains "secrets/credentials.ci.sops.yaml:cloudflare.api_token"
  assert_output_not_contains "${CI_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh detects split Age secret key bech32 payload (case-insensitive)" {
  cd "${MOCK_REPO}"
  git init -q
  mkdir -p tests/scripts
  cat <<EOF >tests/scripts/split_age.bats
@test "split age key" {
  local prefix="AGE-SECRET-KEY-1"
  local body="${PROD_AGE_BODY_LOWER}"
}
EOF
  git add tests/scripts/split_age.bats

  run bash "${LEAK_SCRIPT}" --check-files tests/scripts/split_age.bats
  [ "$status" -eq 1 ]
  assert_output_contains "tests/scripts/split_age.bats:3"
  assert_output_contains "secrets/credentials.sops.yaml:sops_age_key"
  assert_output_not_contains "${PROD_AGE_BODY_LOWER}"
  assert_output_not_contains "${PROD_AGE_BODY}"
}

@test "check-sops-secret-leaks.sh detects individual line of multi-line SSH/PEM private key" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<EOF >leaked_key_fragment.txt
some harmless header
${PROD_PEM_LINE}
some harmless footer
EOF
  git add leaked_key_fragment.txt

  run bash "${LEAK_SCRIPT}" --check-files leaked_key_fragment.txt
  [ "$status" -eq 1 ]
  assert_output_contains "leaked_key_fragment.txt:2"
  assert_output_contains "secrets/credentials.sops.yaml:ssh_priv_key"
  assert_output_not_contains "${PROD_PEM_LINE}"
}

@test "check-sops-secret-leaks.sh ignores allowlisted structural values like gcp.region and dns record type" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' >main.tf
variable "region" {
  default = "us-central1"
}
variable "record_type" {
  default = "A"
}
EOF
  git add main.tf

  run bash "${LEAK_SCRIPT}" --check-files main.tf
  [ "$status" -eq 0 ]
}

@test "check-sops-secret-leaks.sh fails --check-disjointness when CI SOPS duplicates a production secret" {
  cd "${MOCK_REPO}"
  cp "${SHARED_DIR}/secrets/credentials.ci.colliding.sops.yaml" "${MOCK_REPO}/secrets/credentials.ci.sops.yaml"

  run bash "${LEAK_SCRIPT}" --check-disjointness
  [ "$status" -eq 1 ]
  assert_output_contains "cloudflare.api_token"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh fails closed locally when SOPS decryption fails" {
  cd "${MOCK_REPO}"
  git init -q
  echo "hello" >sample.txt
  git add sample.txt
  export SOPS_AGE_KEY_FILE="${BATS_TMPDIR}/nonexistent-age-key.txt"

  run bash "${LEAK_SCRIPT}" --check-files sample.txt
  [ "$status" -eq 1 ]
  assert_output_contains "Failed to decrypt"
}

@test "check-sops-secret-leaks.sh in CI=true skips undecryptable prod SOPS but enforces CI SOPS" {
  cd "${MOCK_REPO}"
  git init -q
  # Corrupt prod SOPS file to simulate missing GPG key in CI
  echo "corrupted-prod-sops" >"${MOCK_REPO}/secrets/credentials.sops.yaml"
  cat <<EOF >ci_leak.txt
token=${CI_TOKEN_VAL}
EOF
  git add ci_leak.txt
  export CI=true

  run bash "${LEAK_SCRIPT}" --check-files ci_leak.txt
  [ "$status" -eq 1 ]
  assert_output_contains "ci_leak.txt:1"
  assert_output_contains "secrets/credentials.ci.sops.yaml:cloudflare.api_token"
  assert_output_not_contains "${CI_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh --all-files scans tracked repository files even when nothing is staged" {
  cd "${MOCK_REPO}"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  cat <<EOF >tracked_leak.bats
# existing tracked file containing a secret that was just added to SOPS
token="${PROD_TOKEN_VAL}"
EOF
  git add tracked_leak.bats
  git commit -q -m "chore: initial tracked file"

  run bash "${LEAK_SCRIPT}" --check-disjointness --all-files
  [ "$status" -eq 1 ]
  assert_output_contains "tracked_leak.bats:2"
  assert_output_contains "secrets/credentials.sops.yaml:cloudflare.api_token"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "lefthook.yml wires sops-secret-leaks, sops-disjointness (--all-files), and verify-sops-encryption (secrets/**) into pre-commit" {
  local lefthook_config="${REPO_ROOT}/lefthook.yml"
  [ -f "$lefthook_config" ]

  run yq '.pre-commit.commands.sops-secret-leaks.run' "$lefthook_config"
  [ "$status" -eq 0 ]
  assert_output_contains "scripts/check-sops-secret-leaks.sh --check-files"

  run yq '.pre-commit.commands.sops-disjointness.run' "$lefthook_config"
  [ "$status" -eq 0 ]
  assert_output_contains "scripts/check-sops-secret-leaks.sh --check-disjointness --all-files"

  run yq '.pre-commit.commands.verify-sops-encryption.glob' "$lefthook_config"
  [ "$status" -eq 0 ]
  assert_output_contains "secrets/**/*.{yml,yaml,json}"
}
