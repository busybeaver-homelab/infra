#!/usr/bin/env bash
# Run gh with one short-lived app token; never use the owner's login.
set +x
set -euo pipefail

refuse() {
  printf 'ERROR: agent gh command is not permitted\n' >&2
  exit 64
}

[[ $# -gt 0 ]] || refuse
# Check every argument, including commands preceded by gh global options.
for arg in "$@"; do
  case "$arg" in
    auth | secret | secrets | variable | variables | ruleset | rulesets | alias | aliases | extension | extensions | ext | ssh-key | gpg-key | --admin*) refuse ;;
  esac
done
repo_value=false
for arg in "$@"; do
  if "$repo_value"; then
    [[ "$arg" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || refuse
    repo_value=false
    continue
  fi
  case "$arg" in
    -R | --repo) repo_value=true ;;
    --repo=*) [[ "${arg#--repo=}" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || refuse ;;
    -R?*) [[ "${arg#-R}" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || refuse ;;
  esac
done
"$repo_value" && refuse
args=" $* "
case "$args" in
  *' repo delete '* | *' repo edit '* | *' repo rename '* | *' repo transfer '*) refuse ;;
esac
if [[ "$args" == *' api '* ]]; then
  for arg in "$@"; do
    case "$arg" in
      # Encoded endpoints and host overrides cannot smuggle privileged API paths.
      *%* | --hostname* | https://* | http://* | //*) refuse ;;
      *rulesets* | */rules/* | *secrets* | *variables* | *environments* | */hooks* | */keys* | */collaborators* | */installations*) refuse ;;
    esac
  done
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This wrapper runs outside the agent sandbox. Any argument naming a local file
# must stay in this checkout or a temporary directory and carry no key material.
repo_root="$(cd "$SCRIPT_DIR/.." && pwd -P)"
tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
system_tmp="$(cd /tmp && pwd -P)"
secret_pattern='-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----|\((protected-)?private-key|AGE-SECRET-KEY-1|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}'
check_file() {
  local path="$1" real
  [[ "$path" != - ]] || return 0
  # A symlink could point anywhere; only real files and directories qualify.
  [[ ! -L "$path" ]] || refuse
  [[ -e "$path" ]] || return 0
  real="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  case "$real" in
    "$repo_root"/secrets | "$repo_root"/secrets/* | "$repo_root"/.git | "$repo_root"/.git/*) refuse ;;
    "$repo_root"/* | "$tmp_root"/* | "$system_tmp"/*) ;;
    *) refuse ;;
  esac
  if [[ -f "$real" ]] && LC_ALL=C grep -aqE -- "$secret_pattern" "$real"; then
    refuse
  fi
}
for arg in "$@"; do
  check_file "$arg"
  [[ "$arg" != *=* ]] || check_file "${arg#*=}"
  [[ "$arg" != *=@* ]] || check_file "${arg#*=@}"
  [[ "$arg" != @* ]] || check_file "${arg#@}"
  [[ "$arg" != -F?* ]] || check_file "${arg#-F}"
  [[ "$arg" != *#* ]] || check_file "${arg%#*}"
done

# shellcheck source=scripts/lib/github-app-token.sh
source "$SCRIPT_DIR/lib/github-app-token.sh"
token="$(github_app_mint_token)" || exit $?
# Clear all ambient token variants, including enterprise credentials.
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_REPO
# Owner aliases can expand into auth/admin commands; owner hosts can supply
# credentials for positional enterprise URLs. Use an empty, private config.
# Extensions remain available through gh's separate data directory.
config_dir="$(mktemp -d)"
trap 'rm -rf "$config_dir"' EXIT
rc=0
# gh extensions and checkout/clone helpers can launch git outside agent-git.sh.
# Block every Git transport in this child tree; network Git uses agent-git.sh.
GH_TOKEN="$token" GH_HOST=github.com GH_CONFIG_DIR="$config_dir" GIT_ALLOW_PROTOCOL='' gh "$@" || rc=$?
exit "$rc"
