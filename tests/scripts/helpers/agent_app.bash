#!/usr/bin/env bash
# Synthetic app fixtures shared by wrapper tests; no live GitHub/SOPS access.
setup_agent_app() {
  export APP_FIXTURE="$BATS_TEST_TMPDIR/app"
  mkdir -p "$APP_FIXTURE/bin"
  openssl genrsa -out "$APP_FIXTURE/key" 2048 2>/dev/null
  export GITHUB_APP_SOPS_FILE="$APP_FIXTURE/credentials.sops.yaml"
  : >"$GITHUB_APP_SOPS_FILE"
  cat >"$APP_FIXTURE/bin/sops" <<'STUB'
#!/usr/bin/env bash
[[ -z "${APP_MINT_FAIL:-}" ]] || exit 1
case "$3" in
  '["github"]["agent_app"]["private_key"]') cat "$APP_FIXTURE/key" ;;
  '["github"]["config"]["agent_app"]["app_id"]') printf '123456' ;;
  '["github"]["config"]["agent_app"]["installation_id"]') printf '7654321' ;;
  '["github"]["config"]["agent_app"]["slug"]') printf 'example-agent' ;;
  '["github"]["config"]["agent_app"]["bot_user_id"]') printf '424242' ;;
  *) exit 1 ;;
esac
STUB
  cat >"$APP_FIXTURE/bin/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
[[ -z "${APP_HTTP_FAIL:-}" ]] || { echo '{"token":"ghs_SYNTHETICtoken0000"}'; exit 22; }
printf '{"token":"ghs_SYNTHETICtoken0000","expires_at":"2026-01-01T00:00:00Z"}\n'
STUB
  chmod +x "$APP_FIXTURE/bin/"*
  prepend_path "$APP_FIXTURE/bin"
}

assert_no_app_token() {
  # shellcheck disable=SC2154 # supplied by bats run
  [[ "$output" != *ghs_SYNTHETICtoken0000* ]] || return 1
}
