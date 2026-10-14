#!/usr/bin/env bats
# Repository guards for OpenTofu state encryption (R2-TF-01, STD-OT-18/19/22).

load 'helpers/test_helper'

ROOT_MODULES=(oci cloudflare gcp azure github homelab monitoring mesh)

@test "no root module ships the retired public default passphrase" {
  run git -C "${REPO_ROOT}" grep -n 'passphrase-default' -- infrastructure scripts .github
  [ "$status" -ne 0 ]
}

@test "every root module declares the passphrase in variables.tf without a default" {
  for m in "${ROOT_MODULES[@]}"; do
    local vars="${REPO_ROOT}/infrastructure/${m}/variables.tf"
    run grep -c '^variable "state_encryption_passphrase"' "$vars"
    [ "$output" = "1" ] || { echo "${m}: variable missing from variables.tf"; return 1; }
    # The block, from its header to the first closing brace at column 0.
    block="$(awk '/^variable "state_encryption_passphrase"/{f=1} f{print} f&&/^}/{exit}' "$vars")"
    run grep -E '^[[:space:]]*default[[:space:]]*=' <<<"$block"
    [ "$status" -ne 0 ] || { echo "${m}: passphrase has a default"; return 1; }
    [[ "$block" == *"sensitive   = true"* ]] || { echo "${m}: not sensitive"; return 1; }
    [[ "$block" == *"length(var.state_encryption_passphrase) >= 32"* ]] || { echo "${m}: no length validation"; return 1; }
    run grep -c 'variable "state_encryption_passphrase"' "${REPO_ROOT}/infrastructure/${m}/encryption.tf"
    [ "$output" = "0" ] || { echo "${m}: variable still declared in encryption.tf"; return 1; }
  done
}

@test "every root module enforces encryption for both state and plan" {
  for m in "${ROOT_MODULES[@]}"; do
    local enc="${REPO_ROOT}/infrastructure/${m}/encryption.tf"
    run grep -c 'enforced = true' "$enc"
    [ "$output" = "2" ] || { echo "${m}: expected enforced = true in state and plan"; return 1; }
    run grep -c 'passphrase    = var.state_encryption_passphrase$' "$enc"
    [ "$output" = "1" ] || { echo "${m}: key provider not bound to the variable"; return 1; }
  done
}

@test "every root module has negative tests for the passphrase validations" {
  for m in "${ROOT_MODULES[@]}"; do
    local neg="${REPO_ROOT}/infrastructure/${m}/tests/negative.tftest.hcl"
    grep -q 'run "reject_short_state_encryption_passphrase"' "$neg" || { echo "${m}: short-passphrase test missing"; return 1; }
    grep -q 'run "reject_placeholder_state_encryption_passphrase"' "$neg" || { echo "${m}: placeholder test missing"; return 1; }
  done
}

@test "test suites set an explicit synthetic passphrase (hermetic, STD-OT-57)" {
  for m in "${ROOT_MODULES[@]}"; do
    for f in "${REPO_ROOT}/infrastructure/${m}/tests/"*.tftest.hcl; do
      # Child-module-only suites never evaluate the root variables.
      grep -q '^variables {' "$f" || continue
      grep -q 'state_encryption_passphrase = "test-only-passphrase-not-a-secret-0001"' "$f" ||
        { echo "${f#"${REPO_ROOT}"/}: no explicit test passphrase"; return 1; }
    done
  done
}

@test ".gitignore keeps local state, state backups, plans and lock info out of git" {
  for path in infrastructure/oci/terraform.tfstate infrastructure/oci/terraform.tfstate.backup \
    infrastructure/github/saved.tfplan infrastructure/mesh/.terraform.tfstate.lock.info; do
    run git -C "${REPO_ROOT}" check-ignore -q "$path"
    [ "$status" -eq 0 ] || { echo "not ignored: $path"; return 1; }
  done
}
