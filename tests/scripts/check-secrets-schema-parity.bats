#!/usr/bin/env bats
# Tests for scripts/check-secrets-schema-parity.sh

load 'helpers/test_helper'

PARITY_SCRIPT="${REPO_ROOT}/scripts/check-secrets-schema-parity.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "check-secrets-schema-parity.sh succeeds on identical key structures" {
  local file_a="${BATS_TMPDIR}/a.yaml"
  local file_b="${BATS_TMPDIR}/b.yaml"

  cat <<'EOF' >"${file_a}"
oci:
  region: dummy
  tenancy_ocid: dummy
is_production: true
sops:
  version: 3.8.1
EOF

  cat <<'EOF' >"${file_b}"
oci:
  region: synthetic
  tenancy_ocid: synthetic
is_production: false
sops:
  version: 3.8.1
EOF

  run bash "${PARITY_SCRIPT}" "${file_a}" "${file_b}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Schema parity verified" ]]
}

@test "check-secrets-schema-parity.sh fails when secondary file is missing a key" {
  local file_a="${BATS_TMPDIR}/a.yaml"
  local file_b="${BATS_TMPDIR}/b.yaml"

  cat <<'EOF' >"${file_a}"
oci:
  region: dummy
  tenancy_ocid: dummy
  private_key: dummy
is_production: true
EOF

  cat <<'EOF' >"${file_b}"
oci:
  region: synthetic
  tenancy_ocid: synthetic
is_production: false
EOF

  run bash "${PARITY_SCRIPT}" "${file_a}" "${file_b}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Schema parity violation" ]] || false
  [[ "$output" =~ "private_key" ]]
}

@test "check-secrets-schema-parity.sh fails when primary file is missing a key" {
  local file_a="${BATS_TMPDIR}/a.yaml"
  local file_b="${BATS_TMPDIR}/b.yaml"

  cat <<'EOF' >"${file_a}"
oci:
  region: dummy
is_production: true
EOF

  cat <<'EOF' >"${file_b}"
oci:
  region: synthetic
  new_key: synthetic
is_production: false
EOF

  run bash "${PARITY_SCRIPT}" "${file_a}" "${file_b}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Schema parity violation" ]] || false
  [[ "$output" =~ "new_key" ]]
}

@test "check-secrets-schema-parity.sh verifies repository canonical secrets files" {
  run bash "${PARITY_SCRIPT}" "${REPO_ROOT}/secrets/credentials.sops.yaml" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Schema parity verified" ]]
}

@test "canonical secrets files define cloudflare_restic schema keys" {
  local keys=("s3_endpoint" "bucket" "s3_access_key_id" "s3_secret_access_key" "password")
  for key in "${keys[@]}"; do
    run yq eval "has(\"cloudflare_restic\") and (.cloudflare_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"cloudflare_restic\") and (.cloudflare_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "canonical secrets files define github repositories config schema keys" {
  local keys=("name" "description" "topics")
  for key in "${keys[@]}"; do
    run yq eval "has(\"github\") and (.github | has(\"config\")) and (.github.config | has(\"repositories\")) and (.github.config.repositories.infra | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"github\") and (.github | has(\"config\")) and (.github.config | has(\"repositories\")) and (.github.config.repositories.infra | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "canonical secrets files define tailscale schema keys" {
  local keys=("client_id" "client_secret")
  for key in "${keys[@]}"; do
    run yq eval "has(\"tailscale\") and (.tailscale | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"tailscale\") and (.tailscale | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "canonical secrets files define tailscale config schema keys" {
  local keys=("tailnet_name" "contact_account_email" "contact_support_email" "contact_security_email")
  for key in "${keys[@]}"; do
    run yq eval "has(\"tailscale\") and (.tailscale | has(\"config\")) and (.tailscale.config | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"tailscale\") and (.tailscale | has(\"config\")) and (.tailscale.config | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "canonical secrets files define gcp schema keys" {
  local keys=("project_id" "region" "zone" "billing_account_id" "budget_alert_recipients" "tailscale_auth_key" "breakglass_user" "breakglass_password" "breakglass_password_hash")
  for key in "${keys[@]}"; do
    run yq eval "has(\"gcp\") and (.gcp | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"gcp\") and (.gcp | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "canonical secrets files define gcp_restic schema keys" {
  local keys=("s3_endpoint" "bucket" "s3_access_key_id" "s3_secret_access_key" "password")
  for key in "${keys[@]}"; do
    run yq eval "has(\"gcp_restic\") and (.gcp_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run yq eval "has(\"gcp_restic\") and (.gcp_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}
