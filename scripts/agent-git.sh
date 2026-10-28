#!/usr/bin/env bash
# Authenticate GitHub transports with the app, independently of owner helpers.
set +x
set -euo pipefail
refuse() {
  printf 'ERROR: agent git requires push, fetch or ls-remote against origin on github.com\n' >&2
  exit 64
}
subcmd="${1:-}"
case "$subcmd" in push | fetch | ls-remote) shift ;; *) refuse ;; esac

# Preserve option order/values; replace only the repository argument (R3).
args=() remote_seen=false option_value=false end_options=false
for arg in "$@"; do
  if "$option_value"; then
    args+=("$arg")
    option_value=false
    continue
  fi
  if ! "$end_options"; then
    case "$arg" in
      --repo* | --all-remotes | --multiple | --upload-pack* | --receive-pack* | --exec*) refuse ;;
      -o | --push-option | --server-option | --depth | --deepen | --shallow-since | --shallow-exclude | --negotiation-tip | -j | --jobs | --filter | --refmap)
        args+=("$arg")
        option_value=true
        continue
        ;;
      --)
        args+=("$arg")
        end_options=true
        continue
        ;;
      -*)
        args+=("$arg")
        continue
        ;;
    esac
  fi
  if ! "$remote_seen"; then
    [[ "$arg" == origin ]] || refuse
    args+=(__AGENT_ORIGIN__)
    remote_seen=true
  else
    args+=("$arg")
  fi
done
"$option_value" && refuse
"$remote_seen" || args+=(__AGENT_ORIGIN__)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/github-app-token.sh
source "$SCRIPT_DIR/lib/github-app-token.sh"
token="$(github_app_mint_token)" || exit $?
# Refuse all rewrite rules, including includes/global config; clearing a
# multi-valued insteadOf setting cannot reliably undo Git's longest-match rule.
rc=0
git config --name-only --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || refuse
origin="$(git remote get-url origin 2>/dev/null)" || refuse
case "$origin" in
  git@github.com:*) repository="${origin#git@github.com:}" ;;
  https://github.com/*) repository="${origin#https://github.com/}" ;;
  *) refuse ;;
esac
repository="${repository%.git}"
[[ "$repository" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*/[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || refuse
url="https://github.com/${repository}.git"
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" != __AGENT_ORIGIN__ ]] || args[i]="$url"
done
# Git shell helpers need shell quoting when the checkout path contains spaces.
printf -v helper '%q' "$SCRIPT_DIR/agent-git-credential.sh"
export AGENT_GIT_TOKEN="$token" AGENT_GIT_PATH="${repository}.git"
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false SSH_ASKPASS=/usr/bin/false
exec git -c credential.helper= -c "credential.helper=!$helper" \
  -c credential.useHttpPath=true -c http.extraHeader= -c "http.$url.extraHeader=" \
  -c protocol.allow=never -c protocol.https.allow=always \
  "$subcmd" "${args[@]}"
