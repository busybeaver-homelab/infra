#!/usr/bin/env bash
# Pre-push guard: rejects pushes to the default branch (refs/heads/main) unless the
# pusher sets ALLOW_MAIN_PUSH=1 for that single command (owner decision D6).
# Agents and automation open pull requests instead.
# It also rejects creating a remote branch that does not contain the default remote
# ref (GUARD_DEFAULT_REMOTE_REF, default refs/remotes/origin/main; STD-CI-73).
#
# Git passes one line per ref on stdin: <local ref> <local sha> <remote ref> <remote sha>
set -euo pipefail

protected_ref="${GUARD_PROTECTED_REF:-refs/heads/main}"
default_remote_ref="${GUARD_DEFAULT_REMOTE_REF:-refs/remotes/origin/main}"
blocked=0

zero_sha="0000000000000000000000000000000000000000"
default_short="${default_remote_ref#refs/remotes/}"

while read -r local_ref local_sha remote_ref remote_sha; do
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
  # A new remote branch (about to become a PR) must start from the latest default
  # branch. Follow-up pushes to an existing branch are left to the merge queue,
  # which tests every entry against the current main.
  elif [ "${local_ref}" != "(delete)" ] && [ "${remote_sha}" = "${zero_sha}" ] &&
    [[ "${remote_ref}" == refs/heads/* ]]; then
    if git rev-parse --verify --quiet "${default_remote_ref}" >/dev/null 2>&1 &&
      git cat-file -e "${local_sha}^{commit}" 2>/dev/null; then
      if ! git merge-base --is-ancestor "${default_remote_ref}" "${local_sha}" 2>/dev/null; then
        echo "ERROR: ${local_ref} is behind ${default_remote_ref}; a new branch must start from the latest default branch." >&2
        echo "       Rebase first (git fetch ${default_short%%/*} ${default_short#*/} && git rebase ${default_short}, or gh stack sync), then push." >&2
        blocked=1
      fi
    fi
  fi
done

exit "${blocked}"
