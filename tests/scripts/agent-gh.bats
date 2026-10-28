#!/usr/bin/env bats
load 'helpers/test_helper'
load 'helpers/agent_app'

setup() {
  REAL_GH="$(command -v gh)"
  setup_agent_app
  WRAPPER="$REPO_ROOT/scripts/agent-gh.sh"
  cat >"$APP_FIXTURE/bin/gh" <<'STUB'
#!/usr/bin/env bash
jq -n --args '$ARGS.positional' -- "$@" >"$APP_FIXTURE/gh.argv"
[[ "${GH_TOKEN:-}" == ghs_SYNTHETICtoken0000 ]] || exit 91
[[ ! -v GITHUB_TOKEN ]] || exit 92
[[ ! -v GH_ENTERPRISE_TOKEN && ! -v GITHUB_ENTERPRISE_TOKEN ]] || exit 93
[[ ! -v GH_REPO ]] || exit 94
if [[ -n "${APP_GH_TRY_GIT:-}" ]]; then
  git ls-remote "$APP_GIT_REMOTE"
  exit $?
fi
printf 'child executed\n'
exit "${APP_GH_EXIT:-0}"
STUB
  chmod +x "$APP_FIXTURE/bin/gh"
}

refused() {
  run bash "$WRAPPER" "$@"
  [ "$status" -eq 64 ]
  [ ! -e "$APP_FIXTURE/gh.argv" ]
  assert_no_app_token
}

@test "passes args unchanged and supplies token only to gh" {
  export GH_TOKEN=ambient GITHUB_TOKEN=ambient GH_ENTERPRISE_TOKEN=ambient GITHUB_ENTERPRISE_TOKEN=ambient
  run bash "$WRAPPER" pr list --search 'label:two words'
  [ "$status" -eq 0 ]
  [ "$output" = 'child executed' ]
  run jq -e '. == ["pr","list","--search","label:two words"]' "$APP_FIXTURE/gh.argv"
  [ "$status" -eq 0 ]
  [ "$GH_TOKEN" = ambient ]
  [ "$GITHUB_TOKEN" = ambient ]
}
@test "refuses auth token" { refused auth token; }
@test "refuses auth login" { refused auth login; }
@test "refuses auth status show-token" { refused auth status --show-token; }
@test "refuses merge admin" { refused pr merge 5 --admin; }
@test "refuses merge admin assignment" { refused pr merge --admin=true 5; }
@test "refuses ruleset API writes after options" { refused api -X PUT repos/o/r/rulesets/1; }
@test "refuses secrets API" { refused api repos/o/r/actions/secrets; }
@test "refuses secret subcommand" { refused secret set X; }
@test "refuses variable subcommand" { refused variable set X; }
@test "refuses ruleset subcommand" { refused ruleset list; }
@test "refuses repo deletion" { refused repo delete; }
@test "refuses auth through global repo flag" { refused --repo o/r auth token; }
@test "refuses merge admin through global repo flag" { refused -R o/r pr merge 5 --admin=true; }
@test "refuses encoded sensitive API endpoint" { refused api repos/o/r/%72ulesets/1; }
@test "refuses foreign API host" { refused api --hostname evil.example.test repos/o/r; }
@test "refuses direct foreign API URL" { refused api https://evil.example.test/repos/o/r; }
@test "refuses missing command" { refused; }

@test "minting failure never runs gh or exposes token" {
  APP_MINT_FAIL=1 run bash "$WRAPPER" pr list
  [ "$status" -eq 3 ]
  [[ "$output" == *scripts/check-gpg-expiry.sh* ]] || false
  [ ! -e "$APP_FIXTURE/gh.argv" ]
  assert_no_app_token
}
@test "HTTP failure never runs gh or exposes response token" {
  APP_HTTP_FAIL=1 run bash "$WRAPPER" pr list
  [ "$status" -eq 5 ]
  [ ! -e "$APP_FIXTURE/gh.argv" ]
  assert_no_app_token
}
@test "preserves gh failure status without printing credentials" {
  APP_GH_EXIT=7 run bash "$WRAPPER" pr checks
  [ "$status" -eq 7 ]
  assert_no_app_token
}
@test "disables xtrace before capturing a token" {
  run bash -x "$WRAPPER" pr list
  [ "$status" -eq 0 ]
  assert_no_app_token
}
@test "allows gh stack through the token child" {
  run bash "$WRAPPER" stack view
  [ "$status" -eq 0 ]
  assert_no_app_token
}

@test "ignores ambient enterprise repository to prevent owner login fallback" {
  GH_REPO=enterprise.example.test/o/r run bash "$WRAPPER" pr list
  [ "$status" -eq 0 ]
  assert_no_app_token
}
@test "refuses enterprise repository flag" { refused pr list -R enterprise.example.test/o/r; }
@test "refuses enterprise repository assignment" { refused pr list --repo=enterprise.example.test/o/r; }

@test "does not load owner gh aliases that can reveal the app token" {
  mkdir -p "$APP_FIXTURE/owner-gh"
  printf 'aliases:\n    show-agent-token: auth token\n' >"$APP_FIXTURE/owner-gh/config.yml"
  rm "$APP_FIXTURE/bin/gh"
  ln -s "$REAL_GH" "$APP_FIXTURE/bin/gh"
  GH_CONFIG_DIR="$APP_FIXTURE/owner-gh" run bash "$WRAPPER" show-agent-token
  [ "$status" -ne 0 ]
  assert_no_app_token
}
@test "runs gh with a clean temporary config and removes it on failure" {
  cat >"$APP_FIXTURE/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s' "$GH_CONFIG_DIR" >"$APP_FIXTURE/gh-config-dir"
[[ ! -e "$GH_CONFIG_DIR/hosts.yml" && ! -e "$GH_CONFIG_DIR/config.yml" ]] || exit 90
exit 7
STUB
  chmod +x "$APP_FIXTURE/bin/gh"
  run bash "$WRAPPER" pr view https://enterprise.example.test/o/r/pull/1
  [ "$status" -eq 7 ]
  local config_dir
  config_dir="$(cat "$APP_FIXTURE/gh-config-dir")"
  [ -n "$config_dir" ]
  [ ! -e "$config_dir" ]
}

@test "gh child cannot fall back to git transport credentials" {
  git init --bare -q "$BATS_TEST_TMPDIR/transport.git"
  export APP_GIT_REMOTE="file://$BATS_TEST_TMPDIR/transport.git"
  export GIT_ALLOW_PROTOCOL=file
  APP_GH_TRY_GIT=1 run bash "$WRAPPER" stack submit --auto
  [ "$status" -eq 128 ]
  [[ "$output" == *"transport 'file' not allowed"* ]] || false
  [ "$GIT_ALLOW_PROTOCOL" = file ]
  assert_no_app_token
}

@test "wrapper can be linted independently with its sourced library" {
  run shellcheck "$WRAPPER"
  [ "$status" -eq 0 ]
}
