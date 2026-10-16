#!/usr/bin/env bats
# Unit tests for scripts/get-tofu-restic-vars.sh using stubbed tofu binary and JSON fixtures.

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/get-tofu-restic-vars.sh"

setup() {
  setup_tmpdir
  FIXTURE_DIR="${BATS_TEST_TMPDIR}/fixtures"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FIXTURE_DIR}" "${STUB_BIN}"

  cat >"${FIXTURE_DIR}/oci.json" <<'EOF'
{
  "backup_s3_endpoint": { "sensitive": true, "value": "https://ns.compat.objectstorage.eu-frankfurt-1.oraclecloud.com" },
  "backup_bucket_name": { "sensitive": true, "value": "homelab-backups-example" },
  "backup_s3_access_key_id": { "sensitive": true, "value": "oci-writer-akid-example" },
  "backup_s3_secret_access_key": { "sensitive": true, "value": "oci-writer-secret-example" }
}
EOF

  cat >"${FIXTURE_DIR}/gcp.json" <<'EOF'
{
  "backup_s3_endpoint": { "sensitive": true, "value": "https://storage.googleapis.com" },
  "backup_bucket_name": { "sensitive": true, "value": "example-homelab-backups" },
  "backup_hmac_access_id": { "sensitive": true, "value": "GOOG1EWRITEREXAMPLE" },
  "backup_hmac_secret": { "sensitive": true, "value": "gcp-writer-hmac-secret-example" }
}
EOF

  cat >"${FIXTURE_DIR}/cloudflare.json" <<'EOF'
{
  "r2_backup_endpoint": { "sensitive": true, "value": "https://00000000000000000000000000000000.r2.cloudflarestorage.com" },
  "r2_backup_bucket_name": { "sensitive": true, "value": "homelab-backups-dr-example" },
  "r2_restic_writer_s3_access_key_id": { "sensitive": true, "value": "cf-r2-writer-akid-example" },
  "r2_restic_writer_s3_secret_access_key": { "sensitive": true, "value": "cf-r2-writer-secret-example" }
}
EOF

  cat >"${FIXTURE_DIR}/monitoring.json" <<'EOF'
{
  "oci_restic_ping_url": { "sensitive": true, "value": "https://hc-ping.com/00000000-0000-0000-0000-000000000001" },
  "gcp_restic_ping_url": { "sensitive": true, "value": "https://hc-ping.com/00000000-0000-0000-0000-000000000002" }
}
EOF
}

teardown() {
  teardown_tmpdir
}

@test "scripts/get-tofu-restic-vars.sh is executable and supports --help" {
  [ -x "${SCRIPT}" ]
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/get-tofu-restic-vars.sh"* ]]
}

@test "scripts/get-tofu-restic-vars.sh assembles OCI, GCP, Cloudflare, and Monitoring JSON outputs" {
  run "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  [ "$status" -eq 0 ]

  run jq -r '.tofu_oci_restic.s3_endpoint' <<<"${output}"
  [ "$output" = "https://ns.compat.objectstorage.eu-frankfurt-1.oraclecloud.com" ]

  run jq -r '.tofu_oci_restic.bucket' <<<"${lines[0]}"
  run "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  [ "$(jq -r '.tofu_oci_restic.bucket' <<<"${output}")" = "homelab-backups-example" ]
  [ "$(jq -r '.tofu_oci_restic.s3_access_key_id' <<<"${output}")" = "oci-writer-akid-example" ]
  [ "$(jq -r '.tofu_oci_restic.s3_secret_access_key' <<<"${output}")" = "oci-writer-secret-example" ]
  [ "$(jq -r '.tofu_oci_restic.healthcheck_url' <<<"${output}")" = "https://hc-ping.com/00000000-0000-0000-0000-000000000001" ]
  [ "$(jq -r '.tofu_gcp_restic.s3_access_key_id' <<<"${output}")" = "GOOG1EWRITEREXAMPLE" ]
  [ "$(jq -r '.tofu_gcp_restic.healthcheck_url' <<<"${output}")" = "https://hc-ping.com/00000000-0000-0000-0000-000000000002" ]
  [ "$(jq -r '.tofu_cloudflare_restic.bucket' <<<"${output}")" = "homelab-backups-dr-example" ]
  [ "$(jq -r '.tofu_cloudflare_restic.s3_access_key_id' <<<"${output}")" = "cf-r2-writer-akid-example" ]
}

@test "scripts/get-tofu-restic-vars.sh fails closed when a required OpenTofu output is missing or empty" {
  cat >"${FIXTURE_DIR}/broken-oci.json" <<'EOF'
{
  "backup_s3_endpoint": { "sensitive": true, "value": "https://ns.compat.objectstorage.eu-frankfurt-1.oraclecloud.com" },
  "backup_bucket_name": { "sensitive": true, "value": "homelab-backups-example" },
  "backup_s3_access_key_id": { "sensitive": true, "value": "" },
  "backup_s3_secret_access_key": { "sensitive": true, "value": "oci-writer-secret-example" }
}
EOF

  run "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/broken-oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR:"* ]]
}
