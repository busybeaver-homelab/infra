#!/usr/bin/env bash
# Pre-push guard: rejects pushes to the default branch (refs/heads/main) unless the
# pusher sets ALLOW_MAIN_PUSH=1 for that single command (owner decision D6).
# Agents and automation open pull requests instead.
#
# Git passes one line per ref on stdin: <local ref> <local sha> <remote ref> <remote sha>
set -euo pipefail

protected_ref="${GUARD_PROTECTED_REF:-refs/heads/main}"
blocked=0

while read -r local_ref _local_sha remote_ref _remote_sha; do
  [ -n "${remote_ref:-}" ] || continue
  if [ "${remote_ref}" = "${protected_ref}" ]; then
    if [ "${local_ref}" = "(delete)" ]; then
      echo "ERROR: refusing to delete ${protected_ref}" >&2
      blocked=1
    elif [ "${ALLOW_MAIN_PUSH:-}" != "1" ]; then
      echo "ERROR: direct push to ${protected_ref} is blocked. Open a pull request," >&2
      echo "       or (repository owner only) re-run with ALLOW_MAIN_PUSH=1 after a fast-forward merge." >&2
      blocked=1
    fi
  fi
done

exit "${blocked}"
