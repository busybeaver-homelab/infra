#!/usr/bin/env bats
# Tests for Tailscale policy files and git-crypt encryption

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PROD_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.hujson"
  CI_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.ci.hujson"
}

@test "tailscale production policy exists and has non-zero size" {
  [ -s "$PROD_POLICY" ]
}

@test "tailscale CI policy exists, has non-zero size, and is valid JSON/HuJSON" {
  [ -s "$CI_POLICY" ]
  python3 -c "import json; json.load(open('$CI_POLICY'))"
}

@test "tailscale production policy is tracked by git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/tailscale/policy.hujson
    [ "$status" -eq 0 ]
    [[ "$output" =~ "encrypted" ]]
  else
    run git check-attr filter infrastructure/tailscale/policy.hujson
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: git-crypt" ]]
  fi
}

@test "tailscale CI policy is explicitly exempted from git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/tailscale/policy.ci.hujson
    [ "$status" -eq 0 ]
    [[ "$output" =~ "not encrypted" ]]
  else
    run git check-attr filter infrastructure/tailscale/policy.ci.hujson
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: unspecified" ]]
  fi
}
