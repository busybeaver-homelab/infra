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
    if ! grep -qE "^[[:space:]]*\|[[:space:]]*(\`${skill}\`|${skill})[[:space:]]*\|" "${REPO_ROOT}/THIRD_PARTY_NOTICES.md"; then
      echo "missing notice: ${skill}" >&2
      missing=1
    fi
  done < <(jq -r '.skills | keys[]' "${REPO_ROOT}/skills-lock.json")
  [ "$missing" -eq 0 ]
}

@test "every vendored skill notice check rejects missing skill or substring match" {
  local fixture
  fixture="$(mktemp)"
  cat <<'EOF' > "$fixture"
| agent-ci-extended | `.agents/skills/agent-ci-extended/` | upstream | MIT | note |
EOF
  run grep -qE "^[[:space:]]*\|[[:space:]]*(\`agent-ci\`|agent-ci)[[:space:]]*\|" "$fixture"
  [ "$status" -ne 0 ]

  run grep -qE "^[[:space:]]*\|[[:space:]]*(\`non-existent-skill\`|non-existent-skill)[[:space:]]*\|" "$fixture"
  [ "$status" -ne 0 ]

  rm -f "$fixture"
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

@test "THIRD_PARTY_NOTICES.md lists no copyleft licence (organisation policy)" {
  run grep -inE '\|[[:space:]]*(MPL|GPL|LGPL|AGPL|EPL|CDDL|EUPL)[-0-9.a-z+]*[[:space:]]*\|' "${REPO_ROOT}/THIRD_PARTY_NOTICES.md"
  [ "$status" -ne 0 ]
}

@test "the MPL-2.0 terraform-style-guide skill stays removed" {
  run jq -e '.skills | has("terraform-style-guide")' "${REPO_ROOT}/skills-lock.json"
  [ "$status" -ne 0 ]
  [ ! -e "${REPO_ROOT}/.agents/skills/terraform-style-guide" ]
}
