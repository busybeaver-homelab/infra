#!/usr/bin/env bats
# Tests for scripts/sync-ops-secrets.sh

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/sync-ops-secrets.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  FAKE_INFRA="$BATS_TEST_TMPDIR/infrastructure"
  mkdir -p "$STUB_BIN" "$FAKE_INFRA/oci" "$FAKE_INFRA/gcp" "$FAKE_INFRA/cloudflare" "$FAKE_INFRA/monitoring"

  export SOPS_FILE="$BATS_TEST_TMPDIR/fake.sops.yaml"
  : >"$SOPS_FILE"

  cat >"$STUB_BIN/tofu" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
chdir=""
for arg in "$@"; do
  case "$arg" in
    -chdir=*) chdir="${arg#-chdir=}" ;;
  esac
done

case "$chdir" in
  */oci)
    cat <<'JSON'
{
  "backup_s3_endpoint": {"sensitive": true, "value": "https://ns.compat.objectstorage.eu-frankfurt-1.example.test"},
  "backup_bucket_name": {"sensitive": true, "value": "homelab-backup-oci-test"},
  "backup_prune_s3_access_key_id": {"sensitive": true, "value": "oci-prune-ak-synthetic"},
  "backup_prune_s3_secret_access_key": {"sensitive": true, "value": "oci-prune-sk-synthetic"},
  "ansible_inventory": {"sensitive": true, "value": {"oci-h1": {"ansible_host": "192.0.2.10"}, "oci-h2": {"ansible_host": "192.0.2.11"}}}
}
JSON
    ;;
  */gcp)
    cat <<'JSON'
{
  "backup_s3_endpoint": {"sensitive": true, "value": "https://storage.example.test"},
  "backup_bucket_name": {"sensitive": true, "value": "homelab-backup-gcp-test"},
  "backup_prune_hmac_access_id": {"sensitive": true, "value": "GOOG1EPRUNESYNTHETIC"},
  "backup_prune_hmac_secret": {"sensitive": true, "value": "gcp-prune-sk-synthetic"},
  "ansible_inventory": {"sensitive": true, "value": {"gcp-h1": {"ansible_host": "198.51.100.10"}}}
}
JSON
    ;;
  */cloudflare)
    cat <<'JSON'
{
  "r2_backup_endpoint": {"sensitive": true, "value": "https://acct.r2.example.test"},
  "r2_backup_bucket_name": {"sensitive": true, "value": "homelab-dr-backup-r2-test"},
  "r2_restic_prune_s3_access_key_id": {"sensitive": true, "value": "r2-prune-ak-synthetic"},
  "r2_restic_prune_s3_secret_access_key": {"sensitive": true, "value": "r2-prune-sk-synthetic"}
}
JSON
    ;;
  */monitoring)
    cat <<'JSON'
{
  "backup_prune_ping_url": {"sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000099"},
  "dr_copy_ping_url": {"sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000102"},
  "ci_schedule_ping_url": {"sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000100"},
  "codeql_schedule_ping_url": {"sensitive": true, "value": "https://hc-ping.example.test/00000000-0000-0000-0000-000000000101"}
}
JSON
    ;;
  *)
    echo "Unexpected -chdir: $chdir" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_BIN/tofu"

  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
extract=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--extract" ]]; then
    extract="$arg"
  fi
  prev="$arg"
done
case "$extract" in
  *'["github"]["owner"]'*) echo "example-owner" ;;
  *'["github"]["token"]'*) echo "ghp_synthetic_token_0000" ;;
  *'["opentofu"]["cloudflare_r2_access_key_id"]'*) echo "backend-ak-synthetic" ;;
  *'["opentofu"]["cloudflare_r2_secret_access_key"]'*) echo "backend-sk-synthetic" ;;
  *'["opentofu"]["state_encryption_passphrase"]'*) echo "backend-passphrase-synthetic-0000000000" ;;
  *'["oci_restic"]["password"]'*) echo "oci-restic-pass-synthetic" ;;
  *'["gcp_restic"]["password"]'*) echo "gcp-restic-pass-synthetic" ;;
  *'["cloudflare_restic"]["password"]'*) echo "r2-restic-pass-synthetic" ;;
  *)
    echo "Unexpected sops extract: $extract" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_BIN/sops"

  cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
val="$(cat)"
printf '%s | stdin=%s\n' "$*" "$val" >> "$BATS_TEST_TMPDIR/gh.calls"
STUB
  chmod +x "$STUB_BIN/gh"

  export PATH="$STUB_BIN:$PATH"
}

@test "sync-ops-secrets.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "sync-ops-secrets.sh passes shellcheck and shfmt" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]

  run shfmt -d -i 2 -ci "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sync-ops-secrets.sh --help displays usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]] || false
  [[ "$output" =~ "--dry-run" ]] || false
  [[ "$output" =~ "--tofu-dir" ]] || false
}

@test "sync-ops-secrets.sh --dry-run prints secret names without calling gh or leaking values" {
  run "$SCRIPT" --dry-run --tofu-dir "$FAKE_INFRA" --sops-file "$SOPS_FILE" --repo "example-owner/infra"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY RUN" ]] || false
  [[ "$output" =~ "OCI_RESTIC_PRUNE_ACCESS_KEY_ID" ]] || false
  [[ "$output" =~ "GCP_RESTIC_PRUNE_ACCESS_KEY_ID" ]] || false
  [[ "$output" =~ "R2_RESTIC_PRUNE_ACCESS_KEY_ID" ]] || false
  [[ "$output" =~ "OCI_BACKUP_HOSTS" ]] || false
  [[ "$output" =~ "GCP_BACKUP_HOSTS" ]] || false
  [[ "$output" =~ "HEALTHCHECKS_BACKUP_PRUNE_PING_URL" ]] || false
  [[ "$output" =~ "HEALTHCHECKS_DR_COPY_PING_URL" ]] || false
  [[ "$output" =~ "HEALTHCHECKS_CI_SCHEDULE_PING_URL" ]] || false
  [[ "$output" =~ "HEALTHCHECKS_CODEQL_SCHEDULE_PING_URL" ]] || false
  [[ ! "$output" =~ "oci-prune-sk-synthetic" ]] || false
  [[ ! "$output" =~ "oci-restic-pass-synthetic" ]] || false
  [[ ! "$output" =~ "oci-h1" ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/gh.calls" ]
}

@test "sync-ops-secrets.sh syncs all 21 restic secrets, backup host lists, and healthchecks ping urls to ops environment" {
  run "$SCRIPT" --tofu-dir "$FAKE_INFRA" --sops-file "$SOPS_FILE"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/gh.calls" ]

  run grep -F "secret set OCI_RESTIC_S3_ENDPOINT --env ops --repo example-owner/infra | stdin=https://ns.compat.objectstorage.eu-frankfurt-1.example.test" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY --env ops --repo example-owner/infra | stdin=oci-prune-sk-synthetic" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set OCI_RESTIC_PASSWORD --env ops --repo example-owner/infra | stdin=oci-restic-pass-synthetic" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set GCP_RESTIC_PRUNE_ACCESS_KEY_ID --env ops --repo example-owner/infra | stdin=GOOG1EPRUNESYNTHETIC" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set GCP_RESTIC_PASSWORD --env ops --repo example-owner/infra | stdin=gcp-restic-pass-synthetic" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set R2_RESTIC_PRUNE_SECRET_ACCESS_KEY --env ops --repo example-owner/infra | stdin=r2-prune-sk-synthetic" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set R2_RESTIC_PASSWORD --env ops --repo example-owner/infra | stdin=r2-restic-pass-synthetic" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set OCI_BACKUP_HOSTS --env ops --repo example-owner/infra | stdin=oci-h1 oci-h2" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set GCP_BACKUP_HOSTS --env ops --repo example-owner/infra | stdin=gcp-h1" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set HEALTHCHECKS_BACKUP_PRUNE_PING_URL --env ops --repo example-owner/infra | stdin=https://hc-ping.example.test/00000000-0000-0000-0000-000000000099" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set HEALTHCHECKS_DR_COPY_PING_URL --env ops --repo example-owner/infra | stdin=https://hc-ping.example.test/00000000-0000-0000-0000-000000000102" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set HEALTHCHECKS_CI_SCHEDULE_PING_URL --env ops --repo example-owner/infra | stdin=https://hc-ping.example.test/00000000-0000-0000-0000-000000000100" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  run grep -F "secret set HEALTHCHECKS_CODEQL_SCHEDULE_PING_URL --env ops --repo example-owner/infra | stdin=https://hc-ping.example.test/00000000-0000-0000-0000-000000000101" "$BATS_TEST_TMPDIR/gh.calls"
  [ "$status" -eq 0 ]

  # Ensure secret values are never echoed to stdout/stderr
  [[ ! "$output" =~ "oci-prune-sk-synthetic" ]] || false
  [[ ! "$output" =~ "r2-restic-pass-synthetic" ]] || false
  [[ ! "$output" =~ "oci-h1" ]] || false

  [ "$(wc -l <"$BATS_TEST_TMPDIR/gh.calls" | tr -d ' ')" -eq 21 ]
}

@test "sync-ops-secrets.sh validates OCI_BACKUP_HOSTS and GCP_BACKUP_HOSTS before the first gh secret write" {
  mv "$STUB_BIN/tofu" "$STUB_BIN/tofu-real"
  cat >"$STUB_BIN/tofu" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == -chdir=*/gcp ]]; then
    cat <<'JSON'
{
  "backup_s3_endpoint": {"sensitive": true, "value": "https://storage.example.test"},
  "backup_bucket_name": {"sensitive": true, "value": "homelab-backup-gcp-test"},
  "backup_prune_hmac_access_id": {"sensitive": true, "value": "GOOG1EPRUNESYNTHETIC"},
  "backup_prune_hmac_secret": {"sensitive": true, "value": "gcp-prune-sk-synthetic"},
  "ansible_inventory": {"sensitive": true, "value": {}}
}
JSON
    exit 0
  fi
done
exec "$(dirname "$0")/tofu-real" "$@"
STUB
  chmod +x "$STUB_BIN/tofu"

  run "$SCRIPT" --tofu-dir "$FAKE_INFRA" --sops-file "$SOPS_FILE" --repo "example-owner/infra"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ansible_inventory" ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/gh.calls" ]
}

@test "sync-ops-secrets.sh fails closed without partial sync when the prune heartbeat URL is missing" {
  mv "$STUB_BIN/tofu" "$STUB_BIN/tofu-real"
  cat >"$STUB_BIN/tofu" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == -chdir=*/monitoring ]]; then
    echo '{}'
    exit 0
  fi
done
exec "$(dirname "$0")/tofu-real" "$@"
STUB
  chmod +x "$STUB_BIN/tofu"

  run "$SCRIPT" --tofu-dir "$FAKE_INFRA" --sops-file "$SOPS_FILE" --repo "example-owner/infra"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "backup_prune_ping_url" ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/gh.calls" ]
}

@test "sync-ops-secrets.sh rejects options without a value" {
  run "$SCRIPT" --repo
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--repo requires a value" ]] || false
}

@test "sync-ops-secrets.sh fails closed when a required OpenTofu output is missing" {
  cat >"$STUB_BIN/tofu" <<'STUB'
#!/usr/bin/env bash
echo '{"backup_s3_endpoint": {"value": ""}}'
STUB
  chmod +x "$STUB_BIN/tofu"

  run "$SCRIPT" --tofu-dir "$FAKE_INFRA" --sops-file "$SOPS_FILE" --repo "example-owner/infra"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ERROR" ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/gh.calls" ]
}
