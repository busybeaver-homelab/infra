#!/usr/bin/env bats
# Tests for the engineering standards runbooks referenced from AGENTS.md (§6)

load 'helpers/test_helper'

RUNBOOKS=(opentofu-standards ansible-standards ci-workflows-standards)

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

# True when the file is git-crypt ciphertext (checkout without the key).
is_encrypted() {
  [ "$(head -c 10 "$1" | tail -c 9)" = "GITCRYPT" ]
}

@test "AGENTS.md references all three standards runbooks" {
  local doc="${REPO_ROOT}/AGENTS.md"
  local rb
  for rb in "${RUNBOOKS[@]}"; do
    run grep -F "docs/runbooks/${rb}.md" "$doc"
    [ "$status" -eq 0 ]
  done
}

@test "every runbook and review-plan path referenced in AGENTS.md exists" {
  local doc="${REPO_ROOT}/AGENTS.md"
  local path
  local missing=0
  # docs/plans examples (e.g. the plan naming example) are illustrative; only
  # runbooks and the infrastructure review plan are real references.
  while IFS= read -r path; do
    if [ ! -e "${REPO_ROOT}/${path}" ]; then
      echo "missing: ${path}" >&2
      missing=1
    fi
  done < <(grep -oE 'docs/(runbooks/[A-Za-z0-9._-]+|plans/[0-9-]+infrastructure-review[A-Za-z0-9._-]*)\.md' "$doc" | sort -u)
  [ "$missing" -eq 0 ]
}

@test "standards runbooks stay under git-crypt encryption" {
  local rb
  for rb in "${RUNBOOKS[@]}"; do
    run git -C "$REPO_ROOT" check-attr filter -- "docs/runbooks/${rb}.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *": filter: git-crypt" ]] || false
  done
}

@test "AGENTS.md keeps precedence over runbooks and documents the encrypted fallback" {
  local doc="${REPO_ROOT}/AGENTS.md"
  run grep -F "never relax or override" "$doc"
  [ "$status" -eq 0 ]
  run grep -F "git-crypt encrypted" "$doc"
  [ "$status" -eq 0 ]
  run grep -F "Runbooks unavailable (encrypted)" "$doc"
  [ "$status" -eq 0 ]
}

@test "runbook rule IDs are unique and every referenced ID is defined" {
  local rb file prefix defined referenced dupes undefined
  for rb in "${RUNBOOKS[@]}"; do
    file="${REPO_ROOT}/docs/runbooks/${rb}.md"
    if is_encrypted "$file"; then
      skip "runbooks are git-crypt encrypted in this checkout"
    fi
    case "$rb" in
      opentofu-standards) prefix="STD-OT" ;;
      ansible-standards) prefix="STD-AN" ;;
      ci-workflows-standards) prefix="STD-CI" ;;
    esac

    # A definition is a rule ID at the start of a heading or bold rule line.
    defined="$(grep -oE "^(#{3,4} |\*\*)${prefix}-[0-9]+" "$file" | grep -oE "${prefix}-[0-9]+")"
    dupes="$(printf '%s\n' "$defined" | sort | uniq -d)"
    if [ -n "$dupes" ]; then
      echo "duplicate rule IDs in ${rb}: ${dupes}" >&2
      false
    fi

    referenced="$(grep -oE "${prefix}-[0-9]+" "$file" | sort -u)"
    undefined="$(printf '%s\n' "$referenced" | grep -vxF -f <(printf '%s\n' "$defined") || true)"
    if [ -n "$undefined" ]; then
      echo "undefined rule IDs referenced in ${rb}: ${undefined}" >&2
      false
    fi
  done
}

@test "runbooks contain no RFC1918 or CGNAT address literals" {
  local rb file
  for rb in "${RUNBOOKS[@]}"; do
    file="${REPO_ROOT}/docs/runbooks/${rb}.md"
    if is_encrypted "$file"; then
      skip "runbooks are git-crypt encrypted in this checkout"
    fi
    run grep -nE '\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01])|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7]))\.[0-9]{1,3}\.[0-9]{1,3}\b' "$file"
    [ "$status" -eq 1 ]
  done
}

@test "AGENTS.md and ci-workflows-standards.md document Merge Queues and Stacked Pull Requests (STD-CI-73)" {
  local agents="${REPO_ROOT}/AGENTS.md"
  run grep -F "gh pr merge" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "gh stack merge" "$agents"
  [ "$status" -eq 0 ]
  run grep -F ".agents/skills/gh-stack/SKILL.md" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "Automated Pull Request Creation, Stacking, and Merge Queue Enrollment:" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "Default-Branch Synchronization Before Opening PRs:" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "git fetch origin main && git rebase origin/main" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "Owner-Review Exception (CODEOWNERS paths):" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "git push --force-with-lease" "$agents"
  [ "$status" -eq 0 ]
  run grep -F -- "--no-track -b <branch> origin/main" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "reachable from the PR head" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "Single PR — Automatic Merge Queue Enrollment:" "$agents"
  [ "$status" -eq 0 ]
  run grep -F "Stacked PRs — Automatic Stack Registration, Submission, and Queueing:" "$agents"
  [ "$status" -eq 0 ]

  local ci_rb="${REPO_ROOT}/docs/runbooks/ci-workflows-standards.md"
  if is_encrypted "$ci_rb"; then
    skip "runbooks are git-crypt encrypted in this checkout"
  fi
  run grep -E "^(#{3,4} |\*\*)STD-CI-73" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "gh stack merge" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "automatically add the single PR to the Merge Queue" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "automatically add Stacked PRs to the stack" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "git fetch origin main && git rebase origin/main" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "Owner-review exception (CODEOWNERS paths):" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "git push --force-with-lease" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "after rebasing or editing an earlier layer" "$ci_rb"
  [ "$status" -eq 0 ]
}

@test "ci-workflows-standards.md requires retiring stale code-scanning configurations (STD-CI-74)" {
  local ci_rb="${REPO_ROOT}/docs/runbooks/ci-workflows-standards.md"
  if is_encrypted "$ci_rb"; then
    skip "runbooks are git-crypt encrypted in this checkout"
  fi
  run grep -E "^### STD-CI-74 " "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "Delete configuration" "$ci_rb"
  [ "$status" -eq 0 ]
  run grep -F "EXPECTED_SARIF_CONFIGS" "$ci_rb"
  [ "$status" -eq 0 ]
}
