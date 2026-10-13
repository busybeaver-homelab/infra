#!/usr/bin/env bats
# Tests for Tailscale policy files and git-crypt encryption

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PROD_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.hujson.tftpl"
  CI_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.ci.hujson.tftpl"
}

@test "tailscale production policy template exists and has non-zero size" {
  [ -s "$PROD_POLICY" ]
}

@test "tailscale CI policy template exists, has non-zero size, and is valid JSON/HuJSON when templated" {
  [ -s "$CI_POLICY" ]
  python3 -c "import json; content = open('$CI_POLICY').read().replace('\${tag_owners}', '{}'); json.loads(content)"
}

@test "tailscale production policy template is tracked by git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/tailscale/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "encrypted" ]]
  else
    run git check-attr filter infrastructure/tailscale/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: git-crypt" ]]
  fi
}

@test "tailscale CI policy template is explicitly exempted from git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/tailscale/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "not encrypted" ]]
  else
    run git check-attr filter infrastructure/tailscale/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: unspecified" ]]
  fi
}
