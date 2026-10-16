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
nextdns:
  accounts:
    account_1:
      account_name: "synthetic-account-label"
      api_key: "prod-nextdns-api-key-998877"
  config:
    accounts:
      account_5:
        profile_name: "synthetic-tailscale-profile"
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
nextdns:
  accounts:
    account_1:
      account_name: "synthetic-account-label"
      api_key: "ci-nextdns-api-key-112233"
  config:
    accounts:
      account_5:
        profile_name: "decoy-profile-5"
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
nextdns:
  accounts:
    account_1:
      account_name: "synthetic-account-label"
      api_key: "ci-nextdns-api-key-112233"
  config:
    accounts:
      account_5:
        profile_name: "decoy-profile-5"
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
  # The bats job itself runs on GitHub Actions; default every test to local mode
  unset CI GITHUB_ACTIONS
}

# Writes stdin to secrets/<name> in the mock repo and SOPS-encrypts it with the test age key.
write_sops() {
  cat >"${MOCK_REPO}/secrets/$1"
  (cd "${MOCK_REPO}" && sops --encrypt --in-place "secrets/$1")
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

@test "check-sops-secret-leaks.sh ignores allowlisted structural values like gcp.region, dns record type, nextdns.accounts.*.account_name, compose.hosts.*.target, and github.config.deploy_keys.*.title" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
gcp:
  region: "us-central1"
compose:
  targets:
    homelab:
      env: |
        # env
  hosts:
    - hostname: "placeholder"
      target: "homelab"
      healthchecks_ping_url: "https://hc-ping.com/<compose_homelab_uuid>"
github:
  config:
    deploy_keys:
      homelab_server:
        title: "Homelab Server"
        key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIProdKeyMaterialForTestingOnly998877"
        read_only: true
nextdns:
  accounts:
    account_1:
      account_name: "synthetic-account-label"
  config:
    accounts:
      account_5:
        profile_name: "synthetic-tailscale-profile"
cloudflare:
  config:
    zones:
      primary:
        dns_records:
          a_1:
            type: "A"
EOF
  cat <<'EOF' | write_sops credentials.ci.sops.yaml
is_production: false
gcp:
  region: "us-central1"
compose:
  targets:
    homelab:
      env: |
        HOMELAB_DUMMY_VAR=decoy-ci-only
  hosts:
    - hostname: "homelab.example.test"
      target: "homelab"
      healthchecks_ping_url: "https://hc-ping.com/<compose_homelab_uuid>"
github:
  config:
    deploy_keys:
      homelab_server:
        title: "Homelab Server"
        key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICIDecoyKeyMaterialForTesting112233"
        read_only: true
EOF
  cat <<'EOF' >main.tf
variable "region" {
  default = "us-central1"
}
variable "record_type" {
  default = "A"
}
variable "nextdns_account_name" {
  default = "synthetic-account-label"
}
variable "nextdns_tailscale_profile_name" {
  default = "synthetic-tailscale-profile"
}
variable "deploy_key_title" {
  default = "Homelab Server"
}
variable "compose_target" {
  default = "homelab"
}
EOF
  git add main.tf

  run bash "${LEAK_SCRIPT}" --check-files main.tf
  [ "$status" -eq 0 ]

  run bash "${LEAK_SCRIPT}" --check-disjointness
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

@test "check-sops-secret-leaks.sh on GitHub Actions skips undecryptable prod SOPS but enforces CI SOPS" {
  cd "${MOCK_REPO}"
  git init -q
  # Corrupt prod SOPS file to simulate the missing GPG key on GitHub Actions
  echo "corrupted-prod-sops" >"${MOCK_REPO}/secrets/credentials.sops.yaml"
  cat <<EOF >ci_leak.txt
token=${CI_TOKEN_VAL}
EOF
  git add ci_leak.txt
  export GITHUB_ACTIONS=true

  run bash "${LEAK_SCRIPT}" --check-files ci_leak.txt
  [ "$status" -eq 1 ]
  assert_output_contains "ci_leak.txt:1"
  assert_output_contains "secrets/credentials.ci.sops.yaml:cloudflare.api_token"
  assert_output_contains "::notice::"
  assert_output_not_contains "${CI_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh on GitHub Actions fails closed when no CI age key is available" {
  cd "${MOCK_REPO}"
  git init -q
  echo "hello" >sample.txt
  git add sample.txt
  unset SOPS_AGE_KEY_FILE
  export HOME="${BATS_TMPDIR}/empty-home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export GITHUB_ACTIONS=true

  run bash "${LEAK_SCRIPT}" --check-files sample.txt
  [ "$status" -eq 1 ]
  assert_output_contains "SOPS_AGE_KEY"
}

@test "check-sops-secret-leaks.sh on GitHub Actions reports that prod/CI disjointness is enforced locally only" {
  cd "${MOCK_REPO}"
  echo "corrupted-prod-sops" >"${MOCK_REPO}/secrets/credentials.sops.yaml"
  export GITHUB_ACTIONS=true

  run bash "${LEAK_SCRIPT}" --check-disjointness
  [ "$status" -eq 0 ]
  assert_output_contains "::notice::"
  assert_output_contains "disjointness"
}

@test "check-sops-secret-leaks.sh does not let a local CI=true bypass fail-closed decryption" {
  cd "${MOCK_REPO}"
  git init -q
  echo "corrupted-prod-sops" >"${MOCK_REPO}/secrets/credentials.sops.yaml"
  echo "hello" >sample.txt
  git add sample.txt
  export CI=true

  run bash "${LEAK_SCRIPT}" --check-files sample.txt
  [ "$status" -eq 1 ]
  assert_output_contains "Failed to decrypt"
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

@test "lefthook.yml does not exempt tracked agent directories from sops-secret-leaks" {
  run yq '.pre-commit.commands.sops-secret-leaks.exclude // ""' "${REPO_ROOT}/lefthook.yml"
  [ "$status" -eq 0 ]
  assert_output_not_contains ".agent"
}

@test "check-sops-secret-leaks.sh scans the staged blob, not the working-tree copy" {
  cd "${MOCK_REPO}"
  git init -q
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >staged_only.txt
  git add staged_only.txt
  echo "cleaned in the working tree but not re-staged" >staged_only.txt

  run bash "${LEAK_SCRIPT}" --check-files staged_only.txt
  [ "$status" -eq 1 ]
  assert_output_contains "staged_only.txt:1"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh ignores an unstaged working-tree change when the staged blob is clean" {
  cd "${MOCK_REPO}"
  git init -q
  echo "clean content" >unstaged.txt
  git add unstaged.txt
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >unstaged.txt

  run bash "${LEAK_SCRIPT}" --check-files unstaged.txt
  [ "$status" -eq 0 ]
}

@test "check-sops-secret-leaks.sh detects a secret inside a staged binary file" {
  cd "${MOCK_REPO}"
  git init -q
  printf 'binary\000header %s\n' "${PROD_TOKEN_VAL}" >blob.bin
  git add blob.bin

  run bash "${LEAK_SCRIPT}" --check-files blob.bin
  [ "$status" -eq 1 ]
  assert_output_contains "blob.bin:1"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh fails closed when the content scanner errors" {
  cd "${MOCK_REPO}"
  git init -q
  echo "hello" >sample.txt
  git add sample.txt
  local real_git shim_dir="${BATS_TMPDIR}/shim"
  real_git="$(command -v git)"
  mkdir -p "${shim_dir}"
  cat <<EOF >"${shim_dir}/git"
#!/usr/bin/env bash
for arg in "\$@"; do
  if [ "\$arg" = "grep" ]; then exit 2; fi
done
exec "${real_git}" "\$@"
EOF
  chmod +x "${shim_dir}/git"
  prepend_path "${shim_dir}"

  run bash "${LEAK_SCRIPT}" --check-files sample.txt
  [ "$status" -eq 1 ]
  assert_output_contains "scanner failed"
}

@test "check-sops-secret-leaks.sh fails closed when a SOPS file decrypts to no values" {
  cd "${MOCK_REPO}"
  git init -q
  echo '{}' | write_sops credentials.ci.sops.yaml
  echo "hello" >sample.txt
  git add sample.txt

  run bash "${LEAK_SCRIPT}" --check-files sample.txt
  [ "$status" -eq 1 ]
  assert_output_contains "no values"
}

@test "check-sops-secret-leaks.sh --check-disjointness detects a production value reused under a different CI key" {
  cd "${MOCK_REPO}"
  cat <<EOF | write_sops credentials.ci.sops.yaml
is_production: false
unrelated:
  other_key: "${PROD_TOKEN_VAL}"
EOF

  run bash "${LEAK_SCRIPT}" --check-disjointness
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.ci.sops.yaml:unrelated.other_key"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh --check-disjointness detects a CI value that embeds a production value" {
  cd "${MOCK_REPO}"
  cat <<EOF | write_sops credentials.ci.sops.yaml
is_production: false
cloudflare:
  api_token: "wrapped-${PROD_TOKEN_VAL}-suffix"
EOF

  run bash "${LEAK_SCRIPT}" --check-disjointness
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.ci.sops.yaml:cloudflare.api_token"
  assert_output_not_contains "${PROD_TOKEN_VAL}"
}

@test "check-sops-secret-leaks.sh anchors the allowlist to schema paths, not key-name suffixes" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
vault:
  action: "vault-action-shaped-secret-7731"
nested:
  key.type: "dotted-key-secret-value-5519"
EOF
  cat <<'EOF' >leak.txt
a = "vault-action-shaped-secret-7731"
b = "dotted-key-secret-value-5519"
EOF
  git add leak.txt

  run bash "${LEAK_SCRIPT}" --check-files leak.txt
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.sops.yaml:vault.action"
  assert_output_contains "secrets/credentials.sops.yaml:nested.key%2Etype"
}

@test "check-sops-secret-leaks.sh applies decoy filters to CI values only, never to production values" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
db:
  password: "Gen<pw>Secret-2026-xyz"
  host: "db-example.internal.example.test"
EOF
  cat <<'EOF' | write_sops credentials.ci.sops.yaml
is_production: false
db:
  password: "ci-decoy-password-<placeholder>"
  host: "db.example.test"
  ip: "203.0.113.50"
EOF
  cat <<'EOF' >ci_decoys.txt
host = "db.example.test"
ip = "203.0.113.50"
EOF
  cat <<'EOF' >prod_leak.txt
pw = "Gen<pw>Secret-2026-xyz"
host = "db-example.internal.example.test"
EOF
  git add ci_decoys.txt prod_leak.txt

  run bash "${LEAK_SCRIPT}" --check-files ci_decoys.txt
  [ "$status" -eq 0 ]

  run bash "${LEAK_SCRIPT}" --check-files prod_leak.txt
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.sops.yaml:db.password"
  assert_output_contains "secrets/credentials.sops.yaml:db.host"
}

@test "check-sops-secret-leaks.sh treats documentation IPs and URL templates as public in both files" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
dns:
  dummy_origin: "192.0.2.1"
  dummy_v6: "2001:db8::1"
storage:
  endpoint: "https://<account_id>.r2.storage.example.com"
  secret_key: "prod-storage-secret-key-4242"
EOF
  cat <<'EOF' >backend.tf
endpoint = "https://<account_id>.r2.storage.example.com"
origin   = "192.0.2.10"
v6       = "2001:db8::1"
EOF
  git add backend.tf

  run bash "${LEAK_SCRIPT}" --check-files backend.tf
  [ "$status" -eq 0 ]

  echo 'key = "prod-storage-secret-key-4242"' >>backend.tf
  git add backend.tf
  run bash "${LEAK_SCRIPT}" --check-files backend.tf
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.sops.yaml:storage.secret_key"
}

@test "check-sops-secret-leaks.sh detects numeric production values" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
telegram:
  chat_id: 98765432101
EOF
  echo 'chat = 98765432101' >numeric.tf
  git add numeric.tf

  run bash "${LEAK_SCRIPT}" --check-files numeric.tf
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.sops.yaml:telegram.chat_id"
}

@test "check-sops-secret-leaks.sh matches 6-7 character values as whole words only" {
  cd "${MOCK_REPO}"
  git init -q
  cat <<'EOF' | write_sops credentials.sops.yaml
is_production: true
alarm:
  pin: "k7x9q2"
EOF
  echo 'pin = "k7x9q2"' >short_leak.txt
  echo 'id = "zzk7x9q2zz"' >embedded.txt
  git add short_leak.txt embedded.txt

  run bash "${LEAK_SCRIPT}" --check-files short_leak.txt
  [ "$status" -eq 1 ]
  assert_output_contains "secrets/credentials.sops.yaml:alarm.pin"

  run bash "${LEAK_SCRIPT}" --check-files embedded.txt
  [ "$status" -eq 0 ]
}

@test "check-sops-secret-leaks.sh scans nested docs folders and non-canonical *.sops.* files" {
  cd "${MOCK_REPO}"
  git init -q
  mkdir -p configuration/roles/demo/docs
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >configuration/roles/demo/docs/notes.md
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >notes.sops.txt
  git add configuration/roles/demo/docs/notes.md notes.sops.txt

  run bash "${LEAK_SCRIPT}" --check-files configuration/roles/demo/docs/notes.md notes.sops.txt
  [ "$status" -eq 1 ]
  assert_output_contains "configuration/roles/demo/docs/notes.md:1"
  assert_output_contains "notes.sops.txt:1"
}

@test "check-sops-secret-leaks.sh relies on clean-filtered (git-crypt style) staged blobs instead of path exemptions" {
  cd "${MOCK_REPO}"
  git init -q
  # Stand-in for git-crypt: the clean filter stores an encoded blob in the index
  git config filter.fakecrypt.clean "base64"
  git config filter.fakecrypt.smudge "cat"
  echo 'docs/** filter=fakecrypt' >.gitattributes
  mkdir -p docs backups
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >docs/plan.md
  printf 'token=%s\n' "${PROD_TOKEN_VAL}" >backups/plain.txt
  git add .gitattributes docs/plan.md backups/plain.txt

  run bash "${LEAK_SCRIPT}" --check-files docs/plan.md
  [ "$status" -eq 0 ]

  # Without the filter the blob is plaintext and must be caught, even under backups/
  run bash "${LEAK_SCRIPT}" --check-files backups/plain.txt
  [ "$status" -eq 1 ]
  assert_output_contains "backups/plain.txt:1"
}

@test "check-sops-secret-leaks.sh never scans the canonical SOPS files or .sops.yaml" {
  cd "${MOCK_REPO}"
  git init -q
  git add .sops.yaml secrets/credentials.sops.yaml secrets/credentials.ci.sops.yaml

  run bash "${LEAK_SCRIPT}" --all-files
  [ "$status" -eq 0 ]
}
