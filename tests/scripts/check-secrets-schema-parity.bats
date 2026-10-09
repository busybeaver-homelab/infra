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

  cat <<'EOF' > "${file_a}"
oci:
  region: dummy
  tenancy_ocid: dummy
is_production: true
sops:
  version: 3.8.1
EOF

  cat <<'EOF' > "${file_b}"
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

  cat <<'EOF' > "${file_a}"
oci:
  region: dummy
  tenancy_ocid: dummy
  private_key: dummy
is_production: true
EOF

  cat <<'EOF' > "${file_b}"
oci:
  region: synthetic
  tenancy_ocid: synthetic
is_production: false
EOF

  run bash "${PARITY_SCRIPT}" "${file_a}" "${file_b}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Schema parity violation" ]]
  [[ "$output" =~ "private_key" ]]
}

@test "check-secrets-schema-parity.sh fails when primary file is missing a key" {
  local file_a="${BATS_TMPDIR}/a.yaml"
  local file_b="${BATS_TMPDIR}/b.yaml"

  cat <<'EOF' > "${file_a}"
oci:
  region: dummy
is_production: true
EOF

  cat <<'EOF' > "${file_b}"
oci:
  region: synthetic
  new_key: synthetic
is_production: false
EOF

  run bash "${PARITY_SCRIPT}" "${file_a}" "${file_b}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Schema parity violation" ]]
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
    run mise exec -- yq "has(\"cloudflare_restic\") and (.cloudflare_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run mise exec -- yq "has(\"cloudflare_restic\") and (.cloudflare_restic | has(\"${key}\"))" "${REPO_ROOT}/secrets/credentials.sops.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

