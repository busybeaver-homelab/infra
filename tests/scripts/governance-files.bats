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

# True when a repository path (leading slash) is owned by a CODEOWNERS pattern with an owner.
is_owned() {
  local file="$1" pattern
  while IFS= read -r pattern; do
    # shellcheck disable=SC2053 # the pattern is a glob on purpose
    if [[ "$pattern" == */ && "$file" == "$pattern"* ]] || [[ "$file" == $pattern ]]; then
      return 0
    fi
  done < <(grep -vE '^\s*(#|$)' "$CODEOWNERS" | awk 'NF >= 2 {print $1}')
  return 1
}

@test "every CODEOWNERS glob pattern matches at least one file" {
  local pattern bad=0
  while IFS= read -r pattern; do
    [[ "$pattern" == *"*"* && "$pattern" != *"**"* ]] || continue
    # shellcheck disable=SC2086 # expand the glob relative to the repository root
    if ! compgen -G "${REPO_ROOT}${pattern}" >/dev/null; then
      echo "CODEOWNERS pattern matches nothing: ${pattern}" >&2
      bad=1
    fi
  done < <(grep -vE '^\s*(#|$)' "$CODEOWNERS" | awk 'NF >= 2 {print $1}')
  [ "$bad" -eq 0 ]
}

@test "every guard script and every lefthook guard is owned (REV2-X-5)" {
  local f bad=0 guards
  guards="$(
    cd "$REPO_ROOT" && {
      ls scripts/{verify,detect,check,block,guard}-*.sh scripts/rotate-state-passphrase.sh 2>/dev/null
      grep -oE 'scripts/(verify|detect|check|block|guard)-[a-z0-9-]+\.sh' lefthook.yml
    } | sort -u
  )"
  # Guard against a vacuous pass: the list itself must not be empty.
  [ "$(grep -c . <<<"$guards")" -ge 8 ]
  while IFS= read -r f; do
    if ! is_owned "/${f}"; then
      echo "unowned guard script: ${f}" >&2
      bad=1
    fi
  done <<<"$guards"
  [ "$bad" -eq 0 ]
}

@test "the ownership check rejects an unowned guard script" {
  run is_owned "/scripts/new-unlisted-guard.sh"
  [ "$status" -eq 1 ]
  run is_owned "/scripts/check-anything-new.sh"
  [ "$status" -eq 0 ]
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

@test "SECURITY.md documents private vulnerability reporting and supported scope (R2-GOV-03)" {
  [ -f "${REPO_ROOT}/SECURITY.md" ]
  run grep -F "GitHub Security Advisories" "${REPO_ROOT}/SECURITY.md"
  [ "$status" -eq 0 ]
  run grep -F "Supported Scope" "${REPO_ROOT}/SECURITY.md"
  [ "$status" -eq 0 ]
  run grep -F "Response Expectations" "${REPO_ROOT}/SECURITY.md"
  [ "$status" -eq 0 ]
}

@test "pull_request_template.md requires diff stat, test exit codes, and file existence checklist (R2-GOV-03)" {
  local tpl="${REPO_ROOT}/.github/pull_request_template.md"
  [ -f "$tpl" ]
  run grep -F "git diff --stat main...HEAD" "$tpl"
  [ "$status" -eq 0 ]
  run grep -F "Tests Run" "$tpl"
  [ "$status" -eq 0 ]
  run grep -F "Referenced Files Exist" "$tpl"
  [ "$status" -eq 0 ]
}

@test "AGENTS.md enforces factual PR evidence, tracker Done evidence, and .agent vs .agents ownership (R2-GOV-03, R2-GOV-04)" {
  run grep -F ".github/pull_request_template.md" "${REPO_ROOT}/AGENTS.md"
  [ "$status" -eq 0 ]
  run grep -F "commit SHA and verification command" "${REPO_ROOT}/AGENTS.md"
  [ "$status" -eq 0 ]
  run grep -F "Agent Directory Ownership" "${REPO_ROOT}/AGENTS.md"
  [ "$status" -eq 0 ]
}

@test ".agent/INSTALL.md pins antigravity-superpowers version (R2-GOV-04)" {
  run grep -E 'npx --yes antigravity-superpowers@[0-9]+\.[0-9]+\.[0-9]+ init' "${REPO_ROOT}/.agent/INSTALL.md"
  [ "$status" -eq 0 ]
}

@test "verify-skills-lock.sh passes against repository skills-lock.json and .agents/skills (R2-GOV-04)" {
  run bash "${REPO_ROOT}/scripts/verify-skills-lock.sh"
  [ "$status" -eq 0 ]
}

@test "verify-skills-lock.sh fails on missing sourceRef or tampered computedHash (R2-GOV-04)" {
  local tmp_lock
  tmp_lock="$(mktemp)"

  jq 'del(.skills["agent-ci"].sourceRef)' "${REPO_ROOT}/skills-lock.json" > "$tmp_lock"
  run env SKILLS_LOCK_FILE="$tmp_lock" bash "${REPO_ROOT}/scripts/verify-skills-lock.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sourceRef"* ]] || false

  jq '.skills["agent-ci"].computedHash = "0000000000000000000000000000000000000000000000000000000000000000"' "${REPO_ROOT}/skills-lock.json" > "$tmp_lock"
  run env SKILLS_LOCK_FILE="$tmp_lock" bash "${REPO_ROOT}/scripts/verify-skills-lock.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hash mismatch"* ]] || false

  rm -f "$tmp_lock"
}

@test "finishing-a-development-branch skill documents single-PR Merge Queue and Stacked PR workflows (STD-CI-73)" {
  local skill="${REPO_ROOT}/.agent/skills/finishing-a-development-branch/SKILL.md"
  [ -f "$skill" ]
  run grep -F "gh pr merge" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "gh stack submit --auto" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "gh stack merge" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "automatically add the single PR to the Merge Queue" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "automatically add Stacked PRs to the stack" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "git fetch origin main && git rebase origin/main" "$skill"
  [ "$status" -eq 0 ]
  run grep -F "gh pr update-branch" "$skill"
  [ "$status" -eq 0 ]

  local wt_skill="${REPO_ROOT}/.agent/skills/using-git-worktrees/SKILL.md"
  [ -f "$wt_skill" ]
  run grep -F "git fetch origin main" "$wt_skill"
  [ "$status" -eq 0 ]
  run grep -F -- '-b "$BRANCH_NAME" origin/main' "$wt_skill"
  [ "$status" -eq 0 ]
}
