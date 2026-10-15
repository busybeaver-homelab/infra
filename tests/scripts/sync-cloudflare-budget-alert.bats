#!/usr/bin/env bats
# Tests for scripts/sync-cloudflare-budget-alert.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/sync-cloudflare-budget-alert.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  export SOPS_FILE="$BATS_TEST_TMPDIR/fake.sops.yaml"
  : >"$SOPS_FILE"

  # Default stub for sops
  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
extract=""
for arg in "$@"; do
  if [[ "$prev" == "--extract" ]]; then
    extract="$arg"
  fi
  prev="$arg"
done
case "$extract" in
  *'["cloudflare"]["api_token"]'*) echo "cftoken_stub_secret_12345" ;;
  *'["cloudflare"]["account_id"]'*) echo "cfaccount_stub_67890" ;;
  *'["cloudflare"]["notification_email"]'*|*'["cloudflare"]["config"]["notification_email"]'*) echo "alerts@example.test" ;;
  *) echo "stub-value" ;;
esac
STUB
  chmod +x "$STUB_BIN/sops"

  # Default stub for curl (simulates GET returning empty policy list, POST creating policy)
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/curl.calls"
for arg in "$@"; do
  if [[ "$arg" == *"POST"* ]] || [[ "${prev:-}" == "-X" && "$arg" == "POST" ]]; then
    echo '{"success": true, "result": {"id": "new-policy-999"}, "errors": [], "messages": []}'
    exit 0
  fi
  prev="$arg"
done
echo '{"success": true, "result": [], "errors": [], "messages": []}'
STUB
  chmod +x "$STUB_BIN/curl"

  export PATH="$STUB_BIN:$PATH"
}

@test "sync-cloudflare-budget-alert.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "sync-cloudflare-budget-alert.sh contains valid bash shebang" {
  head -n 1 "$SCRIPT" | grep -E '^#!/usr/bin/env bash'
}

@test "sync-cloudflare-budget-alert.sh passes shellcheck" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sync-cloudflare-budget-alert.sh passes shfmt check" {
  run shfmt -d -i 2 -ci "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sync-cloudflare-budget-alert: --help displays usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]] || false
  [[ "$output" =~ "--dry-run" ]] || false
  [[ "$output" =~ "--threshold" ]]
}

@test "sync-cloudflare-budget-alert: errors when threshold is invalid" {
  run "$SCRIPT" --threshold "0" --token "test" --account-id "test" --email "test@example.test"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid threshold" ]] || false

  run "$SCRIPT" --threshold "-5" --token "test" --account-id "test" --email "test@example.test"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid threshold" ]] || false

  run "$SCRIPT" --threshold "abc" --token "test" --account-id "test" --email "test@example.test"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid threshold" ]]
}

@test "sync-cloudflare-budget-alert: --dry-run prints planned updates without modifying" {
  run "$SCRIPT" --dry-run --token "super-secret-cf-token-xyz" --account-id "test-acc-id" --email "admin@example.test"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY RUN" ]] || false
  # Ensure raw secret token is masked
  [[ ! "$output" =~ "super-secret-cf-token-xyz" ]] || false
  # In dry-run, only GET should be called, never POST or PUT
  if [ -f "$BATS_TEST_TMPDIR/curl.calls" ]; then
    run grep -E '\-X (POST|PUT)' "$BATS_TEST_TMPDIR/curl.calls"
    [ "$status" -ne 0 ]
  fi
}

@test "sync-cloudflare-budget-alert: idempotent no-op when policy already set to target threshold" {
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/curl.calls"
cat <<'JSON'
{
  "success": true,
  "result": [
    {
      "id": "policy-12345",
      "name": "Billing Budget Alert",
      "description": "Billing Budget Alert",
      "alert_type": "billing_budget_alert",
      "enabled": true,
      "mechanisms": {"email": [{"id": "alerts@example.test"}]},
      "filters": {"total_spend_dollars": ["1"]}
    }
  ],
  "errors": [],
  "messages": []
}
JSON
STUB
  chmod +x "$STUB_BIN/curl"

  run "$SCRIPT" --threshold "1" --token "test" --account-id "test" --email "alerts@example.test"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "already set to \$1 USD" ]] || false

  # Ensure no PUT or POST was executed
  run grep -E '\-X (POST|PUT)' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -ne 0 ]
}

@test "sync-cloudflare-budget-alert: updates policy via PUT when threshold differs" {
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/curl.calls"
for arg in "$@"; do
  if [[ "$arg" == *"PUT"* ]] || [[ "$prev" == "-X" && "$arg" == "PUT" ]]; then
    echo '{"success": true, "result": {"id": "policy-12345"}, "errors": [], "messages": []}'
    exit 0
  fi
  prev="$arg"
done
cat <<'JSON'
{
  "success": true,
  "result": [
    {
      "id": "policy-12345",
      "name": "Billing Budget Alert",
      "description": "Billing Budget Alert",
      "alert_type": "billing_budget_alert",
      "enabled": true,
      "mechanisms": {"email": [{"id": "alerts@example.test"}]},
      "filters": {"total_spend_dollars": ["10"]}
    }
  ],
  "errors": [],
  "messages": []
}
JSON
STUB
  chmod +x "$STUB_BIN/curl"

  run "$SCRIPT" --threshold "1" --token "test" --account-id "test" --email "alerts@example.test"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Updated" || "$output" =~ "updated" ]] || false

  # Verify PUT call with policy ID
  run grep -E 'PUT.*/policies/policy-12345' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]
}

@test "sync-cloudflare-budget-alert: creates policy via POST when policy does not exist" {
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/curl.calls"
for arg in "$@"; do
  if [[ "$arg" == *"POST"* ]] || [[ "$prev" == "-X" && "$arg" == "POST" ]]; then
    echo '{"success": true, "result": {"id": "new-policy-999"}, "errors": [], "messages": []}'
    exit 0
  fi
  prev="$arg"
done
cat <<'JSON'
{
  "success": true,
  "result": [],
  "errors": [],
  "messages": []
}
JSON
STUB
  chmod +x "$STUB_BIN/curl"

  run "$SCRIPT" --threshold "1" --token "test" --account-id "test" --email "alerts@example.test"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Created" || "$output" =~ "created" ]] || false

  # Verify POST call to create policy
  run grep -E 'POST.*/alerting/v3/policies' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]
}

@test "sync-cloudflare-budget-alert: extracts credentials from SOPS file when not provided" {
  run "$SCRIPT" --credentials-file "$SOPS_FILE" --threshold "1"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/curl.calls" ]
  # Secret token must not be printed in logs
  [[ ! "$output" =~ "cftoken_stub_secret_12345" ]]
}

@test "sync-cloudflare-budget-alert: fails closed when SOPS decryption fails and no token is provided" {
  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
echo "SOPS decryption failed" >&2
exit 1
STUB
  chmod +x "$STUB_BIN/sops"

  run "$SCRIPT" --credentials-file "$SOPS_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Failed to extract Cloudflare credentials from SOPS" ]]
}
