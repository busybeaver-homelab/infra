#!/usr/bin/env bats
# Tests for scripts/lib/github-app-token.sh (synthetic values only)

load 'helpers/test_helper'

setup() {
  LIB="$REPO_ROOT/scripts/lib/github-app-token.sh"
  FIX="$BATS_TEST_TMPDIR/fixtures"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  FAKE_TMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$FIX" "$STUB_BIN" "$FAKE_HOME" "$FAKE_TMP"

  openssl genrsa -out "$FIX/key.pem" 2048 2>/dev/null
  openssl rsa -in "$FIX/key.pem" -pubout -out "$FIX/pub.pem" 2>/dev/null
  cp "$FIX/key.pem" "$FIX/private_key"
  printf '123456' >"$FIX/app_id"
  printf '7654321' >"$FIX/installation_id"
  printf 'example-agent' >"$FIX/slug"
  printf '424242' >"$FIX/bot_user_id"

  cat >"$STUB_BIN/sops" <<'STUB'
#!/usr/bin/env bash
extract=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--extract" ]]; then extract="$arg"; fi
  prev="$arg"
done
case "$extract" in
  '["github"]["agent_app"]["private_key"]') name=private_key ;;
  '["github"]["config"]["agent_app"]["app_id"]') name=app_id ;;
  '["github"]["config"]["agent_app"]["installation_id"]') name=installation_id ;;
  '["github"]["config"]["agent_app"]["slug"]') name=slug ;;
  '["github"]["config"]["agent_app"]["bot_user_id"]') name=bot_user_id ;;
  *) exit 1 ;;
esac
[[ -f "$FIXTURE_DIR/$name" ]] || exit 1
cat "$FIXTURE_DIR/$name"
STUB
  cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/curl.argv"
cat >"$BATS_TEST_TMPDIR/curl.stdin"
if [[ -n "${CURL_STUB_FAIL:-}" ]]; then
  echo '{"message":"Bad credentials","leak":"ghs_SYNTHETICtoken0000"}'
  exit 22
fi
echo '{"token":"ghs_SYNTHETICtoken0000","expires_at":"2026-01-01T00:00:00Z"}'
STUB
  chmod +x "$STUB_BIN/sops" "$STUB_BIN/curl"

  export FIXTURE_DIR="$FIX"
  export GITHUB_APP_SOPS_FILE="$BATS_TEST_TMPDIR/fake.sops.yaml"
  : >"$GITHUB_APP_SOPS_FILE"
  prepend_path "$STUB_BIN"
  # shellcheck disable=SC1090
  source "$LIB"
}

b64url_decode() {
  local s="${1//-/+}"
  s="${s//_//}"
  while ((${#s} % 4)); do s+="="; done
  printf '%s' "$s" | openssl base64 -d -A
}

mint() {
  HOME="$FAKE_HOME" TMPDIR="$FAKE_TMP" github_app_mint_token
}

jwt() {
  sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p' "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "library has no side effects on source" {
  run bash -c 'set +e; source "$1"; echo "$-"' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" != *e* ]]
  [[ "$output" != *u* ]]
}

@test "mints a token and prints only the token" {
  run --separate-stderr mint
  [ "$status" -eq 0 ]
  [ "$output" = "ghs_SYNTHETICtoken0000" ]
  [ -z "$stderr" ]
}

@test "JWT header is RS256 and claims are iss=app_id, iat<=now-60, exp-iat<=600" {
  run mint
  [ "$status" -eq 0 ]
  local j h p now
  j="$(jwt)"
  h="$(b64url_decode "${j%%.*}")"
  p="$(b64url_decode "$(cut -d. -f2 <<<"$j")")"
  [ "$(jq -r .alg <<<"$h")" = "RS256" ]
  [ "$(jq -r .typ <<<"$h")" = "JWT" ]
  [ "$(jq -r .iss <<<"$p")" = "123456" ]
  now="$(date +%s)"
  [ "$(jq -r .iat <<<"$p")" -le $((now - 60)) ]
  [ $(($(jq -r .exp <<<"$p") - $(jq -r .iat <<<"$p"))) -le 600 ]
  [ "$(jq -r .exp <<<"$p")" -gt "$now" ]
}

@test "JWT signature verifies with the app public key" {
  run mint
  [ "$status" -eq 0 ]
  local j
  j="$(jwt)"
  printf '%s' "${j%.*}" >"$BATS_TEST_TMPDIR/signing-input"
  b64url_decode "${j##*.}" >"$BATS_TEST_TMPDIR/sig.bin"
  run openssl dgst -sha256 -verify "$FIX/pub.pem" -signature "$BATS_TEST_TMPDIR/sig.bin" "$BATS_TEST_TMPDIR/signing-input"
  [ "$status" -eq 0 ]
}

@test "request narrows repositories to infra and permissions to the fixed set" {
  run mint
  [ "$status" -eq 0 ]
  local body
  body="$(printf '%s\n' "$(cat "$BATS_TEST_TMPDIR/curl.argv")" | grep -m1 '^{')"
  run jq -e '. == {
    repositories: ["infra"],
    permissions: {contents:"write",pull_requests:"write",workflows:"write",checks:"read",statuses:"read",actions:"read",security_events:"read",metadata:"read"}
  }' <<<"$body"
  [ "$status" -eq 0 ]
  grep -q '/app/installations/7654321/access_tokens' "$BATS_TEST_TMPDIR/curl.argv"
}

@test "honours GITHUB_API_URL and GITHUB_APP_REPOSITORY" {
  GITHUB_API_URL="https://ghe.example.test/api/v3" GITHUB_APP_REPOSITORY="other" run mint
  [ "$status" -eq 0 ]
  grep -q 'https://ghe.example.test/api/v3/app/installations/7654321/access_tokens' "$BATS_TEST_TMPDIR/curl.argv"
  grep -q '"repositories":\["other"\]' "$BATS_TEST_TMPDIR/curl.argv"
}

@test "private key is never on curl argv or written under HOME/TMPDIR" {
  run mint
  [ "$status" -eq 0 ]
  ! grep -q 'BEGIN' "$BATS_TEST_TMPDIR/curl.argv"
  ! grep -q 'BEGIN' "$BATS_TEST_TMPDIR/curl.stdin"
  [ -z "$(ls -A "$FAKE_HOME")" ]
  [ -z "$(ls -A "$FAKE_TMP")" ]
}

@test "JWT is not on curl argv" {
  run mint
  [ "$status" -eq 0 ]
  ! grep -q "$(jwt)" "$BATS_TEST_TMPDIR/curl.argv"
}

@test "missing private key exits 3 and names check-gpg-expiry.sh" {
  rm "$FIX/private_key"
  run mint
  [ "$status" -eq 3 ]
  [[ "$output" == ERROR:* ]]
  [[ "$output" == *"scripts/check-gpg-expiry.sh"* ]]
}

@test "missing app_id exits 3" {
  rm "$FIX/app_id"
  run mint
  [ "$status" -eq 3 ]
  [[ "$output" == *"scripts/check-gpg-expiry.sh"* ]]
}

@test "missing installation_id exits 3" {
  rm "$FIX/installation_id"
  run mint
  [ "$status" -eq 3 ]
}

@test "invalid private key exits 4" {
  printf 'not a key' >"$FIX/private_key"
  run mint
  [ "$status" -eq 4 ]
  [[ "$output" == ERROR:* ]]
}

@test "HTTP 401 exits 5 and never prints the response body" {
  CURL_STUB_FAIL=1 run mint
  [ "$status" -eq 5 ]
  [[ "$output" == ERROR:* ]]
  [[ "$output" != *ghs_SYNTHETICtoken0000* ]]
  [[ "$output" != *"Bad credentials"* ]]
}

@test "github_app_identity prints slug[bot] and noreply email" {
  run github_app_identity
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'example-agent[bot]\t424242+example-agent[bot]@users.noreply.github.com')" ]
}

@test "github_app_identity exits 3 when slug is missing" {
  rm "$FIX/slug"
  run github_app_identity
  [ "$status" -eq 3 ]
  [[ "$output" == *"scripts/check-gpg-expiry.sh"* ]]
}
