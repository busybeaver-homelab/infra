#!/usr/bin/env bats
# Unit tests for scripts/get-tofu-restic-vars.sh using stubbed tofu/sops binaries and JSON fixtures.

bats_require_minimum_version 1.5.0

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/get-tofu-restic-vars.sh"

setup() {
  FIXTURE_DIR="${BATS_TEST_TMPDIR}/fixtures"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  FAKE_INFRA="${BATS_TEST_TMPDIR}/infrastructure"
  mkdir -p "${FIXTURE_DIR}" "${STUB_BIN}" "${FAKE_INFRA}"/{oci,gcp,cloudflare,monitoring}

  cat >"${FIXTURE_DIR}/oci.json" <<'EOF'
{
  "backup_s3_endpoint": { "sensitive": true, "value": "https://ns.compat.objectstorage.region.example.test" },
  "backup_bucket_name": { "sensitive": true, "value": "homelab-backups-example" },
  "backup_s3_access_key_id": { "sensitive": true, "value": "oci-writer-akid-example" },
  "backup_s3_secret_access_key": { "sensitive": true, "value": "oci-writer-secret-example" },
  "backup_prune_s3_access_key_id": { "sensitive": true, "value": "oci-prune-akid-example" },
  "backup_prune_s3_secret_access_key": { "sensitive": true, "value": "oci-prune-secret-example" },
  "ansible_inventory": { "sensitive": true, "value": { "h1": { "ansible_host": "192.0.2.10" }, "h2": { "ansible_host": "192.0.2.11" } } }
}
EOF

  cat >"${FIXTURE_DIR}/gcp.json" <<'EOF'
{
  "backup_s3_endpoint": { "sensitive": true, "value": "https://storage.example.test" },
  "backup_bucket_name": { "sensitive": true, "value": "example-homelab-backups" },
  "backup_hmac_access_id": { "sensitive": true, "value": "GOOG1EWRITEREXAMPLE" },
  "backup_hmac_secret": { "sensitive": true, "value": "gcp-writer-hmac-secret-example" },
  "backup_prune_hmac_access_id": { "sensitive": true, "value": "GOOG1EPRUNEREXAMPLE" },
  "backup_prune_hmac_secret": { "sensitive": true, "value": "gcp-prune-hmac-secret-example" },
  "ansible_inventory": { "sensitive": true, "value": { "h1": { "ansible_host": "198.51.100.10" }, "h2": { "ansible_host": "198.51.100.11" } } }
}
EOF

  cat >"${FIXTURE_DIR}/cloudflare.json" <<'EOF'
{
  "r2_backup_endpoint": { "sensitive": true, "value": "https://00000000000000000000000000000000.r2.example.test" },
  "r2_backup_bucket_name": { "sensitive": true, "value": "homelab-backups-dr-example" },
  "r2_restic_prune_s3_access_key_id": { "sensitive": true, "value": "cf-r2-prune-akid-example" },
  "r2_restic_prune_s3_secret_access_key": { "sensitive": true, "value": "cf-r2-prune-secret-example" }
}
EOF

  cat >"${FIXTURE_DIR}/monitoring.json" <<'EOF'
{
  "host_backup_ping_urls": {
    "sensitive": true,
    "value": {
      "h1": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000001",
      "h2": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000002"
    }
  },
  "host_alive_ping_urls": {
    "sensitive": true,
    "value": {
      "h1": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000011",
      "h2": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000012"
    }
  },
  "backup_prune_ping_url": { "sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000003" },
  "dr_copy_ping_url": { "sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000006" },
  "ci_schedule_ping_url": { "sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000004" },
  "codeql_schedule_ping_url": { "sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000005" }
}
EOF

  # tofu stub: serves the fixtures per -chdir module and records the backend env it saw.
  cat >"${STUB_BIN}/tofu" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
chdir=""
for arg in "$@"; do
  case "$arg" in
    -chdir=*) chdir="${arg#-chdir=}" ;;
  esac
done
mod="$(basename "$chdir")"
printf '%s ak=%s region=%s endpoint=%s pass=%s\n' "$mod" "${AWS_ACCESS_KEY_ID:-}" "${AWS_DEFAULT_REGION:-}" \
  "${AWS_ENDPOINT_URL_S3:-}" "${TF_VAR_state_encryption_passphrase:-}" >>"$BATS_TEST_TMPDIR/tofu.calls"
cat "$FIXTURE_DIR/${mod}.json"
STUB
  chmod +x "${STUB_BIN}/tofu"

  cat >"${STUB_BIN}/sops" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "x" >>"$BATS_TEST_TMPDIR/sops.calls"
extract=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--extract" ]]; then
    extract="$arg"
  fi
  prev="$arg"
done
case "$extract" in
  *'["opentofu"]["cloudflare_r2_access_key_id"]'*) echo "backend-ak-synthetic" ;;
  *'["opentofu"]["cloudflare_r2_secret_access_key"]'*) echo "backend-sk-synthetic" ;;
  *'["opentofu"]["state_encryption_passphrase"]'*) echo "backend-passphrase-synthetic-0000000000" ;;
  *'["cloudflare"]["account_id"]'*) echo "00000000000000000000000000000000" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "${STUB_BIN}/sops"

  export FIXTURE_DIR
  export SOPS_FILE="${BATS_TEST_TMPDIR}/fake.sops.yaml"
  : >"${SOPS_FILE}"
  prepend_path "${STUB_BIN}"

  FIXTURE_ARGS=(
    --oci-json "${FIXTURE_DIR}/oci.json"
    --gcp-json "${FIXTURE_DIR}/gcp.json"
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json"
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  )
}


@test "get-tofu-restic-vars.sh is executable, supports --help, and passes shellcheck/shfmt" {
  [ -x "${SCRIPT}" ]
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/get-tofu-restic-vars.sh"* ]] || false
  [[ "$output" == *"--mode <writer|prune>"* ]] || false

  run shellcheck "${SCRIPT}"
  [ "$status" -eq 0 ]
  run shfmt -d -i 2 -ci "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "get-tofu-restic-vars.sh writer mode assembles append-only writer keys and per-host ping URLs without R2 keys" {
  run --separate-stderr "${SCRIPT}" "${FIXTURE_ARGS[@]}"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.tofu_oci_restic.s3_endpoint' <<<"${output}")" = "https://ns.compat.objectstorage.region.example.test" ]
  [ "$(jq -r '.tofu_oci_restic.bucket' <<<"${output}")" = "homelab-backups-example" ]
  [ "$(jq -r '.tofu_oci_restic.s3_access_key_id' <<<"${output}")" = "oci-writer-akid-example" ]
  [ "$(jq -r '.tofu_oci_restic.s3_secret_access_key' <<<"${output}")" = "oci-writer-secret-example" ]
  [ "$(jq -r '.tofu_oci_restic | has("healthcheck_url")' <<<"${output}")" = "false" ]
  [ "$(jq -r '.tofu_gcp_restic.s3_access_key_id' <<<"${output}")" = "GOOG1EWRITEREXAMPLE" ]
  [ "$(jq -r '.tofu_gcp_restic | has("healthcheck_url")' <<<"${output}")" = "false" ]
  [ "$(jq -r 'has("tofu_cloudflare_restic")' <<<"${output}")" = "false" ]
  [ "$(jq -r 'has("dr_copy_ping_url")' <<<"${output}")" = "false" ]
  [ "$(jq -r '.tofu_host_backup_ping_urls.h1' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000001" ]
  [ "$(jq -r '.tofu_host_backup_ping_urls.h2' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000002" ]
  [ "$(jq -r '.tofu_host_alive_ping_urls.h1' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000011" ]
  [ "$(jq -r '.tofu_host_alive_ping_urls.h2' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000012" ]
  [ "$(jq -r 'has("backup_prune_ping_url")' <<<"${output}")" = "false" ]

  # Fixture mode never touches SOPS or tofu.
  [ ! -f "${BATS_TEST_TMPDIR}/sops.calls" ]
  [ ! -f "${BATS_TEST_TMPDIR}/tofu.calls" ]
}

@test "get-tofu-restic-vars.sh prune mode emits delete-capable pruner keys, backup_prune_ping_url, and dr_copy_ping_url" {
  run --separate-stderr "${SCRIPT}" --mode prune "${FIXTURE_ARGS[@]}"
  [ "$status" -eq 0 ]

  [ "$(jq -r '.tofu_oci_restic.s3_access_key_id' <<<"${output}")" = "oci-prune-akid-example" ]
  [ "$(jq -r '.tofu_oci_restic.s3_secret_access_key' <<<"${output}")" = "oci-prune-secret-example" ]
  [ "$(jq -r '.tofu_gcp_restic.s3_access_key_id' <<<"${output}")" = "GOOG1EPRUNEREXAMPLE" ]
  [ "$(jq -r '.tofu_cloudflare_restic.s3_secret_access_key' <<<"${output}")" = "cf-r2-prune-secret-example" ]
  [ "$(jq -r '.backup_prune_ping_url' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000003" ]
  [ "$(jq -r '.dr_copy_ping_url' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000006" ]
  [ "$(jq -r '.ci_schedule_ping_url' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000004" ]
  [ "$(jq -r '.codeql_schedule_ping_url' <<<"${output}")" = "https://hc-ping.example.test/00000000-0000-0000-0000-000000000005" ]
  [ "$(jq -r '.tofu_oci_restic | has("healthcheck_url")' <<<"${output}")" = "false" ]
}

@test "prune mode emits oci_hosts and gcp_hosts from ansible_inventory keys" {
  run --separate-stderr "${SCRIPT}" --mode prune "${FIXTURE_ARGS[@]}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.oci_hosts' <<<"${output}")" = "h1 h2" ]
  [ "$(jq -r '.gcp_hosts' <<<"${output}")" = "h1 h2" ]
}

@test "prune mode fails when ansible_inventory is empty" {
  jq '.ansible_inventory.value = {}' "${FIXTURE_DIR}/oci.json" >"${FIXTURE_DIR}/empty-inv-oci.json"

  run --separate-stderr "${SCRIPT}" --mode prune \
    --oci-json "${FIXTURE_DIR}/empty-inv-oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ansible_inventory"* && "$stderr" == *"oci"* ]] || false
}

@test "get-tofu-restic-vars.sh rejects an unknown --mode and options without a value" {
  run "${SCRIPT}" --mode admin
  [ "$status" -ne 0 ]
  [[ "$output" == *"--mode must be 'writer' or 'prune'"* ]] || false

  run "${SCRIPT}" --oci-json
  [ "$status" -ne 0 ]
  [[ "$output" == *"--oci-json requires a value"* ]] || false
}

@test "get-tofu-restic-vars.sh fails closed with no stdout when a required output is empty" {
  jq '.backup_s3_access_key_id.value = ""' "${FIXTURE_DIR}/oci.json" >"${FIXTURE_DIR}/broken-oci.json"

  run --separate-stderr "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/broken-oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/monitoring.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"ERROR: Missing required OpenTofu output backup_s3_access_key_id in module oci"* ]] || false
}

@test "get-tofu-restic-vars.sh fails closed when a host is missing from host_backup_ping_urls or host_alive_ping_urls" {
  jq 'del(.host_backup_ping_urls.value.h2)' "${FIXTURE_DIR}/monitoring.json" >"${FIXTURE_DIR}/missing-host-backup.json"

  run --separate-stderr "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/missing-host-backup.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"host_backup_ping_urls"* && "$stderr" == *"h2"* ]] || false

  jq '.host_alive_ping_urls.value.h1 = ""' "${FIXTURE_DIR}/monitoring.json" >"${FIXTURE_DIR}/empty-host-alive.json"

  run --separate-stderr "${SCRIPT}" \
    --oci-json "${FIXTURE_DIR}/oci.json" \
    --gcp-json "${FIXTURE_DIR}/gcp.json" \
    --cloudflare-json "${FIXTURE_DIR}/cloudflare.json" \
    --monitoring-json "${FIXTURE_DIR}/empty-host-alive.json"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"host_alive_ping_urls"* && "$stderr" == *"h1"* ]] || false
}

@test "get-tofu-restic-vars.sh live mode reads tofu outputs with SOPS backend credentials, ignoring caller AWS_* keys" {
  export AWS_ACCESS_KEY_ID="caller-restic-ak-must-not-reach-backend"
  export AWS_SECRET_ACCESS_KEY="caller-restic-sk-must-not-reach-backend"

  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tofu_oci_restic.s3_access_key_id' <<<"${output}")" = "oci-writer-akid-example" ]

  [ "$(wc -l <"${BATS_TEST_TMPDIR}/tofu.calls" | tr -d ' ')" -eq 4 ]
  run grep -c "ak=backend-ak-synthetic region=auto endpoint=https://00000000000000000000000000000000.r2.cloudflarestorage.com pass=backend-passphrase-synthetic-0000000000" "${BATS_TEST_TMPDIR}/tofu.calls"
  [ "$output" = "4" ]
  run grep -F "caller-restic-ak" "${BATS_TEST_TMPDIR}/tofu.calls"
  [ "$status" -ne 0 ]

  # Backend secrets are decrypted once per invocation, not once per module.
  [ "$(wc -l <"${BATS_TEST_TMPDIR}/sops.calls" | tr -d ' ')" -le 5 ]
}

@test "get-tofu-restic-vars.sh live mode fails closed when a module cannot be read" {
  cat >"${STUB_BIN}/tofu" <<'STUB'
#!/usr/bin/env bash
echo "Error: Backend initialization required" >&2
exit 1
STUB
  chmod +x "${STUB_BIN}/tofu"

  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Failed to read OpenTofu outputs from infrastructure/oci"* ]] || false
}

@test "get-tofu-restic-vars.sh live mode fails closed when SOPS backend secrets cannot be decrypted" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"${STUB_BIN}/sops"
  chmod +x "${STUB_BIN}/sops"

  run --separate-stderr "${SCRIPT}" --tofu-dir "${FAKE_INFRA}"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Could not decrypt opentofu."* ]] || false
  [ ! -f "${BATS_TEST_TMPDIR}/tofu.calls" ]
}
