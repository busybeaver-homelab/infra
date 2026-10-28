#!/usr/bin/env bash
# Apply the app's bot identity to one linked worktree, preserving owner config.
set +x
set -euo pipefail
refuse() {
  printf 'ERROR: provide a linked, non-bare worktree path\n' >&2
  exit 64
}
[[ $# -eq 1 && -d "$1" ]] || refuse
worktree="$(cd "$1" && pwd -P)"
git_dir="$(git -C "$worktree" rev-parse --absolute-git-dir 2>/dev/null)" || refuse
common_dir="$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null)" || refuse
common_dir="$(cd "$worktree" && cd "$common_dir" && pwd -P)"
[[ "$git_dir" != "$common_dir" ]] || refuse
[[ -z "$(git -C "$worktree" rev-parse --show-superproject-working-tree)" ]] || refuse
[[ "$(git -C "$worktree" rev-parse --is-bare-repository)" == false ]] || refuse
# Enabling worktreeConfig requires migration of unusual shared core.worktree or
# core.bare=true setups. Refuse them rather than changing another checkout.
if git -C "$worktree" config --local --get core.worktree >/dev/null 2>&1 ||
  [[ "$(git -C "$worktree" config --local --get core.bare || true)" == true ]]; then
  refuse
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/github-app-token.sh
source "$SCRIPT_DIR/lib/github-app-token.sh"
identity="$(github_app_identity)" || exit $?
IFS=$'\t' read -r name email <<<"$identity"
[[ -n "$name" && -n "$email" && "$identity" != *$'\n'* ]] || exit 3
git -C "$worktree" config --local extensions.worktreeConfig true
git -C "$worktree" config --worktree user.name "$name"
git -C "$worktree" config --worktree user.email "$email"
git -C "$worktree" config --worktree commit.gpgsign false
