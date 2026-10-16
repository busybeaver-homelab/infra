#!/usr/bin/env bats
# Tests for Tailscale policy files and git-crypt encryption

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PROD_POLICY="${REPO_ROOT}/infrastructure/mesh/policy.hujson.tftpl"
  CI_POLICY="${REPO_ROOT}/infrastructure/mesh/policy.ci.hujson.tftpl"
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
    run git-crypt status infrastructure/mesh/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "encrypted" ]] || false
  else
    run git check-attr filter infrastructure/mesh/policy.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: git-crypt" ]] || false
  fi
}

@test "tailscale CI policy template is explicitly exempted from git-crypt" {
  if command -v git-crypt >/dev/null 2>&1; then
    run git-crypt status infrastructure/mesh/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "not encrypted" ]] || false
  else
    run git check-attr filter infrastructure/mesh/policy.ci.hujson.tftpl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "filter: unspecified" ]] || false
  fi
}

@test "tailscale CI policy template strictly uses decoy NextDNS profile ID and target" {
  run grep -E '"nextdns:000000"' "$CI_POLICY"
  [ "$status" -eq 0 ]

  run grep -E '"tag:decoy-client"' "$CI_POLICY"
  [ "$status" -eq 0 ]

  # Ensure no non-decoy nextdns attribute exists
  run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.loads(f.read().replace('\${tag_owners}', '{}'))
for item in data.get('nodeAttrs', []):
    for attr in item.get('attr', []):
        if attr.startswith('nextdns:') and attr != 'nextdns:000000':
            sys.exit(1)
" "$CI_POLICY"
  [ "$status" -eq 0 ]
}
