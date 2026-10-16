#!/usr/bin/env bats
# Unit tests for scripts/drift-cloudflare.sh using stubbed tofu/sops (no network, no real secrets).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/drift-cloudflare.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN" "$BATS_TEST_TMPDIR/module"
  export SOPS_FILE="$BATS_TEST_TMPDIR/fake.sops.yaml"
  : >"$SOPS_FILE"

  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
echo "S3CR3T-VALUE"
STUB
  cat >"$STUB_BIN/tofu" <<'STUB'
#!/usr/bin/env bash
args=" $* "
case "$args" in
  *" init "*) exit "${STUB_INIT_RC:-0}" ;;
  *" plan "*)
    if [ "${STUB_PLAN_RC:-0}" -eq 1 ]; then
      echo "Error: boom on 0123456789abcdef0123456789abcdef for user@example.org with S3CR3T-VALUE" >&2
    fi
    exit "${STUB_PLAN_RC:-0}"
    ;;
  *" show "*)
    cat <<'JSON'
{"resource_changes":[
 {"address":"cloudflare_zone_setting.this[\"ssl\"]","change":{"actions":["update"],"before":{"value":"S3CR3T-VALUE"},"after":{"value":"strict"}}},
 {"address":"cloudflare_dns_record.this[\"a_1\"]","change":{"actions":["no-op"]}}
]}
JSON
    ;;
esac
STUB
  chmod +x "$STUB_BIN/sops" "$STUB_BIN/tofu"
  export PATH="$STUB_BIN:$PATH"
}

@test "exits 0 and reports no drift when the plan is clean" {
  STUB_PLAN_RC=0 run "$SCRIPT" --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No drift"* ]] || false
  [[ "$output" != *"S3CR3T-VALUE"* ]] || false
}

@test "exits 2 and prints counts and addresses (never values) on drift" {
  STUB_PLAN_RC=2 run "$SCRIPT" --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 2 ]
  [[ "$output" == *"update: 1"* ]] || false
  [[ "$output" == *'cloudflare_zone_setting.this["ssl"]'* ]] || false
  [[ "$output" != *"S3CR3T-VALUE"* ]] || false
  [[ "$output" != *"strict"* ]] || false
}

@test "exits 1 on plan errors and masks IDs, emails and secrets in the error output" {
  STUB_PLAN_RC=1 run "$SCRIPT" --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: boom"* ]] || false
  [[ "$output" != *"0123456789abcdef0123456789abcdef"* ]] || false
  [[ "$output" != *"user@example.org"* ]] || false
  [[ "$output" != *"S3CR3T-VALUE"* ]] || false
}

@test "exits 1 when init fails" {
  STUB_INIT_RC=1 run "$SCRIPT" --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 1 ]
  [[ "$output" == *"init failed"* ]] || false
}

@test "mise exposes the drift:cloudflare task" {
  run grep -E '^\[tasks\."drift:cloudflare"\]' "$REPO_ROOT/mise.toml"
  [ "$status" -eq 0 ]
}

@test "scripts/drift.sh masks 6-hex NextDNS profile IDs for dns module and pings Healthchecks" {
  local curl_log="$BATS_TEST_TMPDIR/curl.log"
  cat >"$STUB_BIN/curl" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$curl_log"
STUB
  chmod +x "$STUB_BIN/curl"

  STUB_PLAN_RC=0 HEALTHCHECKS_DRIFT_PING_URL="https://hc-ping.example.com/00000000-0000-0000-0000-000000000000" \
    run "$REPO_ROOT/scripts/drift.sh" --module dns --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 0 ]
  grep -q "https://hc-ping.example.com/00000000-0000-0000-0000-000000000000$" "$curl_log"

  : >"$curl_log"
  STUB_PLAN_RC=2 HEALTHCHECKS_DRIFT_PING_URL="https://hc-ping.example.com/00000000-0000-0000-0000-000000000000" \
    run "$REPO_ROOT/scripts/drift.sh" --module dns --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 2 ]
  grep -q "https://hc-ping.example.com/00000000-0000-0000-0000-000000000000/fail$" "$curl_log"
}

@test "scripts/drift.sh exports TF_VARs and passes R2 endpoint to tofu init, and treats output-only changes as no drift" {
  local env_log="$BATS_TEST_TMPDIR/tofu_env.log"
  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
{
  "opentofu": {
    "cloudflare_r2_access_key_id": "r2-id-test",
    "cloudflare_r2_secret_access_key": "r2-secret-test",
    "state_encryption_passphrase": "test-passphrase-at-least-32-chars"
  },
  "cloudflare": {
    "api_token": "cf-api-token-test",
    "account_id": "11111111111111111111111111111111"
  }
}
JSON
STUB
  cat >"$STUB_BIN/tofu" <<STUB
#!/usr/bin/env bash
args=" \$* "
case "\$args" in
  *" init "*)
    echo "INIT_ARGS=\$*" >>"$env_log"
    exit 0
    ;;
  *" plan "*)
    echo "TF_VAR_state_encryption_passphrase=\${TF_VAR_state_encryption_passphrase:-}" >>"$env_log"
    echo "TF_VAR_cloudflare_api_token=\${TF_VAR_cloudflare_api_token:-}" >>"$env_log"
    echo "TF_VAR_cloudflare_account_id=\${TF_VAR_cloudflare_account_id:-}" >>"$env_log"
    exit 2
    ;;
  *" show "*)
    cat <<'JSON'
{"resource_changes":[
  {"address":"data.tailscale_devices.all","change":{"actions":["read"]}}
],"output_changes":{
  "devices":{"actions":["update"]}
}}
JSON
    ;;
esac
STUB
  chmod +x "$STUB_BIN/sops" "$STUB_BIN/tofu"

  run "$REPO_ROOT/scripts/drift.sh" --module cloudflare --module-dir "$BATS_TEST_TMPDIR/module"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No drift"* ]]
  grep -q 'endpoint=https://11111111111111111111111111111111.r2.cloudflarestorage.com' "$env_log"
  grep -q 'TF_VAR_state_encryption_passphrase=test-passphrase-at-least-32-chars' "$env_log"
  grep -q 'TF_VAR_cloudflare_api_token=cf-api-token-test' "$env_log"
  grep -q 'TF_VAR_cloudflare_account_id=11111111111111111111111111111111' "$env_log"
}
