#!/usr/bin/env bash
# scripts/verify-commit-msg.sh
# Validates Conventional Commits format and branch naming conventions.
#
# Usage: verify-commit-msg.sh <commit-msg-file>
# Exit codes:
#   0 = Valid commit message and branch name
#   1 = Invalid commit message or branch name

set -euo pipefail

if [[ $# -lt 1 || ! -f "$1" ]]; then
  echo "ERROR: Missing or unreadable commit message file: ${1:-<empty>}" >&2
  exit 1
fi

msg_file="$1"

# Extract first non-comment, non-empty line
commit_msg=""
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments starting with '#' and whitespace-only lines
  if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
    continue
  fi
  commit_msg="$line"
  break
done <"$msg_file"

if [[ -z "$commit_msg" ]]; then
  echo "ERROR: Commit message is empty." >&2
  exit 1
fi

# 1. Validate Conventional Commit Format
# Format: <type>[(<scope>)][!]: <description>
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
readonly CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([-a-zA-Z0-9_./]+\))?(!)?: .+'

if [[ ! "$commit_msg" =~ $CC_REGEX ]]; then
  echo "ERROR: Invalid commit message format." >&2
  echo "Commit messages must follow the Conventional Commits specification:" >&2
  echo "  <type>(<scope>): <subject>" >&2
  echo "" >&2
  echo "Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert" >&2
  echo "Examples:" >&2
  echo "  feat(ci): add unified ci gate" >&2
  echo "  fix: handle empty commit message edge case" >&2
  echo "  chore(deps)!: bump major version across toolchain" >&2
  echo "" >&2
  echo "Your message was:" >&2
  echo "  $commit_msg" >&2
  exit 1
fi

# 2. Validate Branch Naming Convention
# Format: <type>/<scope>/<short-desc>
# Exempt: main, master, HEAD (detached)
current_branch="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$current_branch" ]]; then
  current_branch="HEAD"
fi

if [[ "$current_branch" != "main" && "$current_branch" != "master" && "$current_branch" != "HEAD" ]]; then
  readonly BRANCH_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)/[-a-zA-Z0-9_.]+/[-a-zA-Z0-9_.]+$'

  if [[ ! "$current_branch" =~ $BRANCH_REGEX ]]; then
    echo "ERROR: Invalid branch name '$current_branch'." >&2
    echo "Branch name must follow the pattern: <type>/<scope>/<short-desc>" >&2
    echo "Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert" >&2
    echo "Examples:" >&2
    echo "  feat/ci/make-gates-real" >&2
    echo "  fix/secrets/containment" >&2
    echo "  chore/deps/bump-actions" >&2
    exit 1
  fi
fi

exit 0
