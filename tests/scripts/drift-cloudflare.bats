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
