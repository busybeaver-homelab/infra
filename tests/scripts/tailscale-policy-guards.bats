#!/usr/bin/env bats
# Tests for Tailscale policy files and git-crypt encryption

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  if [ -f "${REPO_ROOT}/infrastructure/tailscale/policy.hujson.tftpl" ]; then
    PROD_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.hujson.tftpl"
    CI_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.ci.hujson.tftpl"
    IS_TEMPLATE=true
  else
    PROD_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.hujson"
    CI_POLICY="${REPO_ROOT}/infrastructure/tailscale/policy.ci.hujson"
    IS_TEMPLATE=false
  fi
}

@test "tailscale production policy exists and has non-zero size" {
  [ -s "$PROD_POLICY" ]
}

@test "tailscale CI policy exists, has non-zero size, and is valid JSON/HuJSON" {
  [ -s "$CI_POLICY" ]
  if [ "$IS_TEMPLATE" = "true" ]; then
    python3 -c "import json; content = open('$CI_POLICY').read().replace('\${tag_owners}', '{}'); json.loads(content)"
  else
    python3 -c "import json; json.load(open('$CI_POLICY'))"
  fi
}

@test "tailscale production policy is tracked by git-crypt" {
  run git-crypt status "${PROD_POLICY#$REPO_ROOT/}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "encrypted" ]]
}

@test "tailscale CI policy is explicitly exempted from git-crypt" {
  run git-crypt status "${CI_POLICY#$REPO_ROOT/}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not encrypted" ]]
}
