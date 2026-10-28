#!/usr/bin/env bats
load 'helpers/test_helper'
load 'helpers/agent_app'

setup() {
  export REAL_GIT="$(command -v git)"
  setup_agent_app
  WRAPPER="$REPO_ROOT/scripts/agent-git.sh"
  HELPER="$REPO_ROOT/scripts/agent-git-credential.sh"
  export APP_ORIGIN=git@github.com:example-org/example-repo.git
  cat >"$APP_FIXTURE/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'called\n' >>"$APP_FIXTURE/git.calls"
if [[ "$1" == config ]]; then
  "$REAL_GIT" "$@"
  exit $?
fi

if [[ "$*" == 'remote get-url origin' ]]; then
  printf '%s\n' "$APP_ORIGIN"
  exit 0
fi
if [[ -n "${APP_INSPECT_HTTP:-}" ]]; then
  config_args=()
  while [[ "${1:-}" == -c ]]; do config_args+=("$1" "$2"); shift 2; done
  "$REAL_GIT" "${config_args[@]}" config --get-urlmatch http.extraHeader https://github.com/example-org/example-repo.git
  exit $?
fi
if [[ -n "${APP_INSPECT_CREDENTIALS:-}" ]]; then
  config_args=()
  while [[ "${1:-}" == -c ]]; do config_args+=("$1" "$2"); shift 2; done
  printf 'protocol=https\nhost=github.com\npath=example-org/example-repo.git\n\n' |
    "$REAL_GIT" "${config_args[@]}" credential fill
  exit $?
fi
jq -n --args '$ARGS.positional' -- "$@" >"$APP_FIXTURE/git.argv"
[[ "${AGENT_GIT_TOKEN:-}" == ghs_SYNTHETICtoken0000 ]] || exit 91
[[ "${GIT_TERMINAL_PROMPT:-}" == 0 ]] || exit 92
[[ "${GIT_ASKPASS:-}" == /usr/bin/false ]] || exit 93
printf 'git child executed\n'
exit "${APP_GIT_EXIT:-0}"
STUB
  chmod +x "$APP_FIXTURE/bin/git"
}

refused() {
  run bash "$WRAPPER" "$@"
  [ "$status" -eq 64 ]
  [ ! -e "$APP_FIXTURE/git.argv" ]
  assert_no_app_token
}

helper_get() {
  printf 'protocol=https\nhost=github.com\npath=example-org/example-repo.git\n\n' |
    AGENT_GIT_TOKEN=ghs_SYNTHETICtoken0000 AGENT_GIT_PATH=example-org/example-repo.git bash "$HELPER" get
}

@test "push replaces origin with HTTPS and clears credential helpers first" {
  run bash "$WRAPPER" push -u origin HEAD
  [ "$status" -eq 0 ]
  [ "$output" = 'git child executed' ]
  run jq -e '.[0:3] == ["-c","credential.helper=","-c"] and (.[3] | startswith("credential.helper=!")) and .[-4:] == ["push","-u","https://github.com/example-org/example-repo.git","HEAD"]' "$APP_FIXTURE/git.argv"
  [ "$status" -eq 0 ]
}
@test "push inserts origin URL when no remote is supplied" {
  run bash "$WRAPPER" push
  [ "$status" -eq 0 ]
  run jq -e '.[-2:] == ["push","https://github.com/example-org/example-repo.git"]' "$APP_FIXTURE/git.argv"
  [ "$status" -eq 0 ]
}
@test "accepts HTTPS origin without dot git" {
  APP_ORIGIN=https://github.com/example-org/example-repo run bash "$WRAPPER" fetch origin
  [ "$status" -eq 0 ]
  assert_no_app_token
}
@test "fetch preserves option values when finding the remote" {
  run bash "$WRAPPER" fetch --depth 1 origin main
  [ "$status" -eq 0 ]
  run jq -e '.[-5:] == ["fetch","--depth","1","https://github.com/example-org/example-repo.git","main"]' "$APP_FIXTURE/git.argv"
  [ "$status" -eq 0 ]
}
@test "allows ls-remote" {
  run bash "$WRAPPER" ls-remote origin 'refs/heads/*'
  [ "$status" -eq 0 ]
  assert_no_app_token
}
@test "refuses commit" { refused commit -m x; }
@test "refuses config" { refused config user.name x; }
@test "refuses remote" { refused remote set-url origin https://example.test/repo; }
@test "refuses alternate remote" { refused push other HEAD; }
@test "refuses arbitrary URL" { refused push https://evil.example.test/o/r HEAD; }
@test "refuses repo override" { refused push --repo=https://evil.example.test/o/r; }
@test "refuses URL rewriting origin" {
  APP_ORIGIN=https://evil.example.test/o/r run bash "$WRAPPER" push origin HEAD
  [ "$status" -eq 64 ]
  [ ! -e "$APP_FIXTURE/git.argv" ]
  assert_no_app_token
}
@test "minting failure never invokes git" {
  APP_MINT_FAIL=1 run bash "$WRAPPER" push origin HEAD
  [ "$status" -eq 3 ]
  [ ! -e "$APP_FIXTURE/git.calls" ]
  [[ "$output" == *scripts/check-gpg-expiry.sh* ]] || false
  assert_no_app_token
}
@test "HTTP failure never invokes git or leaks response" {
  APP_HTTP_FAIL=1 run bash "$WRAPPER" push origin HEAD
  [ "$status" -eq 5 ]
  [ ! -e "$APP_FIXTURE/git.calls" ]
  assert_no_app_token
}
@test "preserves git exit status and never traces the token" {
  APP_GIT_EXIT=7 run bash -x "$WRAPPER" push origin HEAD
  [ "$status" -eq 7 ]
  assert_no_app_token
}
@test "helper answers get over credential protocol" {
  run helper_get
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'username=x-access-token\npassword=ghs_SYNTHETICtoken0000')" ]
}
@test "helper store and erase are silent" {
  for action in store erase; do
    AGENT_GIT_TOKEN=ghs_SYNTHETICtoken0000 run bash "$HELPER" "$action"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}
@test "helper fails closed without a token" {
  run bash "$HELPER" get </dev/null
  [ "$status" -eq 1 ]
  assert_no_app_token
}
@test "helper refuses foreign host" {
  run bash -c 'printf "protocol=https\nhost=evil.example.test\n\n" | AGENT_GIT_TOKEN=ghs_SYNTHETICtoken0000 bash "$1" get' _ "$HELPER"
  [ "$status" -eq 1 ]
  assert_no_app_token
}
@test "helper refuses a different repository" {
  run bash -c 'printf "protocol=https\nhost=github.com\npath=other/repo.git\n\n" | AGENT_GIT_PATH=example-org/example-repo.git AGENT_GIT_TOKEN=ghs_SYNTHETICtoken0000 bash "$1" get' _ "$HELPER"
  [ "$status" -eq 1 ]
  assert_no_app_token
}

@test "refuses pushInsteadOf configuration before transport" {
  "$REAL_GIT" init -q "$BATS_TEST_TMPDIR/rewrite"
  cd "$BATS_TEST_TMPDIR/rewrite"
  "$REAL_GIT" config url.git@github.com:.pushInsteadOf https://github.com/
  refused push origin HEAD
}
@test "refuses insteadOf configuration before transport" {
  "$REAL_GIT" init -q "$BATS_TEST_TMPDIR/rewrite"
  cd "$BATS_TEST_TMPDIR/rewrite"
  "$REAL_GIT" config url.git@github.com:.insteadOf https://github.com/
  refused fetch origin
}
@test "clears URL-specific owner Authorization headers" {
  "$REAL_GIT" init -q "$BATS_TEST_TMPDIR/http-config"
  cd "$BATS_TEST_TMPDIR/http-config"
  "$REAL_GIT" config http.https://github.com/.extraHeader 'Authorization: Basic SYNTHETIC_OWNER_CREDENTIAL'
  APP_INSPECT_HTTP=1 run bash "$WRAPPER" push origin HEAD
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clears URL-specific owner credential helpers before real Git credential lookup" {
  "$REAL_GIT" init -q "$BATS_TEST_TMPDIR/owner-helper"
  cd "$BATS_TEST_TMPDIR/owner-helper"
  "$REAL_GIT" config credential.https://github.com/.helper '!touch "$APP_FIXTURE/owner-helper-called"; printf "username=owner\npassword=SYNTHETIC_OWNER_CREDENTIAL\n"'
  "$REAL_GIT" config credential.https://github.com/.useHttpPath false
  APP_INSPECT_CREDENTIALS=1 run bash "$WRAPPER" push origin HEAD
  [ "$status" -eq 0 ]
  [ ! -e "$APP_FIXTURE/owner-helper-called" ]
  [[ "$output" == *password=ghs_SYNTHETICtoken0000* ]] || false
}
