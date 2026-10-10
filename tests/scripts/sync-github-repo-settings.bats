#!/usr/bin/env bats
# Tests for scripts/sync-github-repo-settings.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/sync-github-repo-settings.sh"
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
  *'["github"]["token"]'*) echo "ghp_stub_secret_token_12345" ;;
  *'["github"]["owner"]'*) echo "busybeaver-homelab" ;;
  *) echo "stub-value" ;;
esac
STUB
  chmod +x "$STUB_BIN/sops"

  # Default stub for curl
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/curl.calls"
echo '{"message": "success"}'
STUB
  chmod +x "$STUB_BIN/curl"

  export PATH="$STUB_BIN:$PATH"
}

@test "sync-github-repo-settings.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "sync-github-repo-settings.sh contains valid bash shebang" {
  head -n 1 "$SCRIPT" | grep -E '^#!/usr/bin/env bash'
}

@test "sync-github-repo-settings.sh passes shellcheck" {
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sync-github-repo-settings.sh passes shfmt check" {
  run shfmt -d -i 2 -ci "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "sync-github-repo-settings: --help displays usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "--dry-run" ]]
  [[ "$output" =~ "--repo" ]]
}

@test "sync-github-repo-settings: errors when repo argument is invalid" {
  run "$SCRIPT" --repo "invalidformat" --token "fake-token"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Invalid repository format" ]]
}

@test "sync-github-repo-settings: --dry-run prints planned updates without modifying" {
  run "$SCRIPT" --dry-run --repo "test-owner/test-repo" --token "super-secret-token-xyz"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY RUN" ]]
  [[ "$output" =~ "test-owner/test-repo" ]]
  # Ensure raw secret token is masked
  [[ ! "$output" =~ "super-secret-token-xyz" ]]
  # Ensure curl was NOT invoked in dry run
  [ ! -f "$BATS_TEST_TMPDIR/curl.calls" ]
}

@test "sync-github-repo-settings: executes expected REST API calls with curl" {
  run "$SCRIPT" --repo "test-owner/test-repo" --token "super-secret-token-xyz"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/curl.calls" ]

  # Check immutable releases call
  run grep -E '/repos/test-owner/test-repo/immutable-releases' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]

  # Check artifact and log retention call
  run grep -E '/repos/test-owner/test-repo/actions/permissions/artifact-and-log-retention' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]

  # Check fork PR contributor approval call
  run grep -E '/repos/test-owner/test-repo/actions/permissions/fork-pr-contributor-approval' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]

  # Check vulnerability alerts call
  run grep -E '/repos/test-owner/test-repo/vulnerability-alerts' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]

  # Check security and analysis patch call
  run grep -E 'PATCH.*/repos/test-owner/test-repo' "$BATS_TEST_TMPDIR/curl.calls"
  [ "$status" -eq 0 ]
}

@test "sync-github-repo-settings: extracts token and owner from SOPS file when not provided" {
  run "$SCRIPT" --credentials-file "$SOPS_FILE" --repo "busybeaver-homelab/infra"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/curl.calls" ]
  [[ ! "$output" =~ "ghp_stub_secret_token_12345" ]]
}

@test "sync-github-repo-settings: fails closed when SOPS decryption fails and no token is provided" {
  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
echo "SOPS decryption failed" >&2
exit 1
STUB
  chmod +x "$STUB_BIN/sops"

  run "$SCRIPT" --credentials-file "$SOPS_FILE" --repo "busybeaver-homelab/infra"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Failed to extract GitHub token from SOPS" ]]
}
