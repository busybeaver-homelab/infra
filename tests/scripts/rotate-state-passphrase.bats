#!/usr/bin/env bats
# Tests for scripts/rotate-state-passphrase.sh. The integration tests run real OpenTofu
# against a local backend with the builtin terraform_data resource: offline, no providers.

load 'helpers/test_helper'

ROTATE="${REPO_ROOT}/scripts/rotate-state-passphrase.sh"
PASS_A="test-only-rotation-passphrase-aaaaaaaaaaaa"
PASS_B="test-only-rotation-passphrase-bbbbbbbbbbbb"
PASS_C="test-only-rotation-passphrase-cccccccccccc"

# Creates infrastructure/<name> with the repository's real encryption.tf and a local backend.
make_module() {
  local dir="${INFRA}/$1"
  mkdir -p "$dir"
  cp "${REPO_ROOT}/infrastructure/github/encryption.tf" "$dir/encryption.tf"
  cat >"$dir/backend.tf" <<EOF
terraform {
  backend "local" {
    path = "${INFRA}/$1.tfstate"
  }
}
EOF
  cat >"$dir/variables.tf" <<'EOF'
variable "state_encryption_passphrase" {
  type      = string
  sensitive = true
}
EOF
  cat >"$dir/main.tf" <<'EOF'
resource "terraform_data" "marker" {
  input = "rotation-test"
}
EOF
}

# Runs tofu in a module with the given passphrase.
tofu_in() {
  local module="$1" pass="$2"
  shift 2
  TF_VAR_state_encryption_passphrase="$pass" tofu -chdir="${INFRA}/${module}" "$@"
}

setup() {
  INFRA="${BATS_TEST_TMPDIR}/infra"
  export INFRA_DIR="${INFRA}"
  mkdir -p "$INFRA"
}

requires_tofu() {
  command -v tofu >/dev/null || skip "tofu not on PATH"
}

@test "next_provider_name appends and increments a generation suffix" {
  source "$ROTATE"
  [ "$(next_provider_name state_passphrase)" = "state_passphrase_v2" ]
  [ "$(next_provider_name state_passphrase_v2)" = "state_passphrase_v3" ]
  [ "$(next_provider_name state_passphrase_v19)" = "state_passphrase_v20" ]
}

@test "current_provider_name reads the committed encryption.tf of every module" {
  source "$ROTATE"
  for enc in "${REPO_ROOT}"/infrastructure/*/encryption.tf; do
    run current_provider_name "$enc"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^state_passphrase(_v[0-9]+)?$ ]] || false
  done
}

@test "current_provider_name refuses a config that is already mid-rotation" {
  source "$ROTATE"
  printf '%s\n' 'key_provider "pbkdf2" "a" {' '}' 'key_provider "pbkdf2" "b" {' '}' >"${BATS_TEST_TMPDIR}/enc.tf"
  run current_provider_name "${BATS_TEST_TMPDIR}/enc.tf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rotation already in progress"* ]] || false
}

@test "refuses to run without both passphrases and leaves encryption.tf untouched" {
  make_module demo
  before="$(cat "${INFRA}/demo/encryption.tf")"
  run env -u TF_VAR_state_encryption_passphrase_previous TF_VAR_state_encryption_passphrase="$PASS_B" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"TF_VAR_state_encryption_passphrase_previous"* ]] || false
  [ "$(cat "${INFRA}/demo/encryption.tf")" = "$before" ]
}

@test "refuses a new passphrase shorter than 32 characters or equal to the current one" {
  make_module demo
  run env TF_VAR_state_encryption_passphrase="short" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"at least 32 characters"* ]] || false
  run env TF_VAR_state_encryption_passphrase="$PASS_A" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"equals the current one"* ]] || false
}

@test "aborts without --yes unless the operator types rotate" {
  make_module demo
  run bash -c "echo no | TF_VAR_state_encryption_passphrase='$PASS_B' TF_VAR_state_encryption_passphrase_previous='$PASS_A' bash '$ROTATE' demo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted."* ]] || false
  grep -q 'key_provider "pbkdf2" "state_passphrase" {' "${INFRA}/demo/encryption.tf"
}

@test "re-encrypts existing state, renames the provider and never prints a passphrase" {
  requires_tofu
  make_module demo
  tofu_in demo "$PASS_A" init -input=false >/dev/null
  tofu_in demo "$PASS_A" apply -auto-approve -input=false >/dev/null
  serial_before="$(tofu_in demo "$PASS_A" state pull | jq .serial)"
  lineage_before="$(tofu_in demo "$PASS_A" state pull | jq -r .lineage)"

  run env TF_VAR_state_encryption_passphrase="$PASS_B" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo: state re-encrypted (key_provider.pbkdf2.state_passphrase -> state_passphrase_v2)"* ]] || false
  [[ "$output" != *"$PASS_A"* ]] || false
  [[ "$output" != *"$PASS_B"* ]] || false

  # The committed config now names the new provider everywhere, and only once.
  grep -q 'key_provider "pbkdf2" "state_passphrase_v2" {' "${INFRA}/demo/encryption.tf"
  [ "$(grep -c 'key_provider.pbkdf2.state_passphrase_v2' "${INFRA}/demo/encryption.tf")" -eq 1 ]
  run grep -qE '"state_passphrase"|pbkdf2\.state_passphrase([^_]|$)' "${INFRA}/demo/encryption.tf"
  [ "$status" -ne 0 ]

  # The new passphrase alone reads the state; the old one is rejected; nothing else changed.
  run tofu_in demo "$PASS_B" state list
  [ "$status" -eq 0 ]
  [[ "$output" == *"terraform_data.marker"* ]] || false
  run tofu_in demo "$PASS_A" state list
  [ "$status" -ne 0 ]
  [ "$(tofu_in demo "$PASS_B" state pull | jq .serial)" = "$serial_before" ]
  [ "$(tofu_in demo "$PASS_B" state pull | jq -r .lineage)" = "$lineage_before" ]
  run tofu_in demo "$PASS_B" plan -detailed-exitcode -input=false
  [ "$status" -eq 0 ]
}

@test "a second rotation chains from v2 to v3" {
  requires_tofu
  make_module demo
  tofu_in demo "$PASS_A" init -input=false >/dev/null
  tofu_in demo "$PASS_A" apply -auto-approve -input=false >/dev/null
  TF_VAR_state_encryption_passphrase="$PASS_B" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes demo >/dev/null

  run env TF_VAR_state_encryption_passphrase="$PASS_C" TF_VAR_state_encryption_passphrase_previous="$PASS_B" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"state_passphrase_v2 -> state_passphrase_v3"* ]] || false
  run tofu_in demo "$PASS_C" state list
  [ "$status" -eq 0 ]
}

@test "fails closed when the previous passphrase is wrong and changes nothing" {
  requires_tofu
  make_module demo
  tofu_in demo "$PASS_A" init -input=false >/dev/null
  tofu_in demo "$PASS_A" apply -auto-approve -input=false >/dev/null

  run env TF_VAR_state_encryption_passphrase="$PASS_C" TF_VAR_state_encryption_passphrase_previous="$PASS_B" \
    bash "$ROTATE" --yes demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the state"* ]] || false
  grep -q 'key_provider "pbkdf2" "state_passphrase" {' "${INFRA}/demo/encryption.tf"
  run tofu_in demo "$PASS_A" state list
  [ "$status" -eq 0 ]
}

@test "a module without remote state is only renamed" {
  requires_tofu
  make_module fresh
  run env TF_VAR_state_encryption_passphrase="$PASS_B" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes fresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh: no remote state yet"* ]] || false
  grep -q 'key_provider "pbkdf2" "state_passphrase_v2" {' "${INFRA}/fresh/encryption.tf"
}

@test "--all rotates every module that has an encryption.tf" {
  requires_tofu
  make_module one
  make_module two
  mkdir -p "${INFRA}/tests"
  run env TF_VAR_state_encryption_passphrase="$PASS_B" TF_VAR_state_encryption_passphrase_previous="$PASS_A" \
    bash "$ROTATE" --yes --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"one: renamed"* ]] || false
  [[ "$output" == *"two: renamed"* ]] || false
  [[ "$output" != *"tests:"* ]] || false
}
