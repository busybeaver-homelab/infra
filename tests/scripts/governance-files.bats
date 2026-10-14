#!/usr/bin/env bats
# Tests for repository governance files: LICENSE, THIRD_PARTY_NOTICES.md and CODEOWNERS

load 'helpers/test_helper'

CODEOWNERS="${REPO_ROOT}/.github/CODEOWNERS"

@test "LICENSE is an explicit all-rights-reserved reference notice" {
  run grep -F "All rights reserved." "${REPO_ROOT}/LICENSE"
  [ "$status" -eq 0 ]
  run grep -F "published for reference only" "${REPO_ROOT}/LICENSE"
  [ "$status" -eq 0 ]
  run grep -F "THIRD_PARTY_NOTICES.md" "${REPO_ROOT}/LICENSE"
  [ "$status" -eq 0 ]
}

@test "every vendored skill in skills-lock.json is listed in THIRD_PARTY_NOTICES.md" {
  local skill missing=0
  while IFS= read -r skill; do
    if ! grep -qF "| ${skill} |" "${REPO_ROOT}/THIRD_PARTY_NOTICES.md"; then
      echo "missing notice: ${skill}" >&2
      missing=1
    fi
  done < <(jq -r '.skills | keys[]' "${REPO_ROOT}/skills-lock.json")
  [ "$missing" -eq 0 ]
}

@test "every owned CODEOWNERS path exists in the repository" {
  local path missing=0
  while IFS= read -r path; do
    [[ "$path" == *"*"* ]] && continue
    if [ ! -e "${REPO_ROOT}${path}" ]; then
      echo "CODEOWNERS path does not exist: ${path}" >&2
      missing=1
    fi
  done < <(grep -vE '^\s*(#|$)' "$CODEOWNERS" | awk 'NF >= 2 {print $1}')
  [ "$missing" -eq 0 ]
}

@test "CODEOWNERS does not own paths that Renovate updates" {
  local owned
  owned="$(grep -vE '^\s*(#|$)' "$CODEOWNERS" | awk 'NF >= 2 {print $1}')"
  run grep -E '^/?(\.github/workflows|\.github/actions|\.github/renovate\.json5|mise\.(toml|lock)|uv\.lock|pyproject\.toml|configuration/roles/requirements\.yml)' <<< "$owned"
  [ "$status" -eq 1 ]
}

@test "Renovate-managed files inside owned directories are explicitly unowned" {
  run grep -E '^/infrastructure/github/\*\*/versions\.tf[[:space:]]*$' "$CODEOWNERS"
  [ "$status" -eq 0 ]
  run grep -E '^/infrastructure/github/\*\*/\.terraform\.lock\.hcl[[:space:]]*$' "$CODEOWNERS"
  [ "$status" -eq 0 ]
}
