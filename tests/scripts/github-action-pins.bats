#!/usr/bin/env bats
# Tests for pinned GitHub Actions commit SHAs across workflows and actions

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "all external GitHub Actions uses directives are pinned to 40-character commit SHAs" {
  local invalid_pins=0
  while IFS= read -r line; do
    # Extract uses: target (remove filename/line prefix, 'uses:', whitespace, and comments)
    local target
    target="$(echo "$line" | sed -E 's/^.*:[0-9]+:[[:space:]]*uses:[[:space:]]*//' | sed -E 's/[[:space:]]*#.*$//')"

    # Skip local composite actions starting with ./
    if [[ "$target" =~ ^\./ ]]; then
      continue
    fi

    # Check that target matches owner/repo(/path)?@40-char-sha
    if [[ ! "$target" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(/[^@]+)?@[a-f0-9]{40}$ ]]; then
      echo "Invalid or unpinned action reference: $line (parsed target: '$target')" >&2
      invalid_pins=$((invalid_pins + 1))
    fi
  done < <(grep -rnE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$REPO_ROOT/.github/workflows/" "$REPO_ROOT/.github/actions/")

  [ "$invalid_pins" -eq 0 ]
}

@test "actions/cache is pinned to verified valid commit SHA d4323d4df104b026a6aa633fdb11d772146be0bf" {
  local count
  count=$(grep -rcE 'uses:[[:space:]]*actions/cache@d4323d4df104b026a6aa633fdb11d772146be0bf' "$REPO_ROOT/.github/" | awk -F: '{s+=$2} END {print s}')
  [ "$count" -ge 3 ]

  # Ensure no corrupted SHAs exist
  run grep -rnE 'actions/cache@(d4323d4df104b026a6aa633fdb11d772115b6fe8|d4323d4df104b026a6aa633fdb11d772115f6ec1)' "$REPO_ROOT/.github/"
  [ "$status" -ne 0 ]
}

@test "jdx/mise-action is pinned to verified valid commit SHA 5083fe46898c414b2475087cc79da59e7da859e8" {
  local count
  count=$(grep -rcE 'uses:[[:space:]]*jdx/mise-action@5083fe46898c414b2475087cc79da59e7da859e8' "$REPO_ROOT/.github/" | awk -F: '{s+=$2} END {print s}')
  [ "$count" -ge 3 ]

  # Ensure no corrupted SHAs exist
  run grep -rnE 'jdx/mise-action@af40da49309fc57bf9e1a1795c643666d933a049' "$REPO_ROOT/.github/"
  [ "$status" -ne 0 ]
}

@test "aquasecurity/trivy-action composite action is not used to comply with action security policies" {
  run grep -rnE 'uses:[[:space:]]*aquasecurity/trivy-action' "$REPO_ROOT/.github/"
  [ "$status" -ne 0 ]
}

@test "no unresolvable or corrupted action commit SHAs exist in .github/" {
  run grep -rnE '(d4323d4df104b026a6aa633fdb11d772115b6fe8|d4323d4df104b026a6aa633fdb11d772115f6ec1|af40da49309fc57bf9e1a1795c643666d933a049|18f259c5e261ebd1660144983293406f5c128cb5)' "$REPO_ROOT/.github/"
  [ "$status" -ne 0 ]
}
