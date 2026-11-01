#!/usr/bin/env bash
# Authenticate GitHub transports with the app, independently of owner helpers.
set +x
set -euo pipefail
refuse() {
  printf 'ERROR: agent git requires push, fetch or ls-remote against origin on github.com\n' >&2
  exit 64
}
# Ambient hook and config overrides must not reach this unsandboxed Git.
unset ALLOW_MAIN_PUSH "${!GUARD_@}" "${!LEFTHOOK@}" "${!GIT_CONFIG@}"
subcmd="${1:-}"
case "$subcmd" in push | fetch | ls-remote) shift ;; *) refuse ;; esac

# Preserve option order/values; replace only the repository argument (R3).
args=() refspecs=() remote_seen=false option_value=false end_options=false
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
        # Pushes keep their hooks and cannot delete, mirror or force-overwrite refs.
        # Git accepts unambiguous prefixes of long options, so match those too.
        if [[ "$subcmd" == push ]]; then
          [[ ! "$arg" =~ ^-[A-Za-z0-9]*[df] ]] || refuse
          name="${arg%%=*}"
          for forbidden in --no-verify --mirror --delete --all --branches --prune --force; do
            [[ ${#name} -lt 3 || "$forbidden" != "$name"* ]] || refuse
          done
        fi
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
    # main changes only through the merge queue; agents never push it.
    if [[ "$subcmd" == push && ("$arg" == :* || "$arg" == +* || "${arg##*:}" =~ ^(refs/)?(heads/)?main$) ]]; then
      refuse
    fi
    refspecs+=("$arg")
    args+=("$arg")
  fi
done
"$option_value" && refuse
"$remote_seen" || args+=(__AGENT_ORIGIN__)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/github-app-token.sh
source "$SCRIPT_DIR/lib/github-app-token.sh"
token="$(github_app_mint_token)" || exit $?
origin="$(git remote get-url origin 2>/dev/null)" || refuse
case "$origin" in
  git@github.com:*) repository="${origin#git@github.com:}" ;;
  https://github.com/*) repository="${origin#https://github.com/}" ;;
  *) refuse ;;
esac
repository="${repository%.git}"
[[ "$repository" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*/[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || refuse
url="https://github.com/${repository}.git"
# Checks see the temporary remote, so hasconfig includes resolve as at run time.
probe=(git -c "remote.agentapp.url=$url")
# Refuse all rewrite rules, including includes/global config; clearing a
# multi-valued insteadOf setting cannot reliably undo Git's longest-match rule.
rc=0
"${probe[@]}" config --name-only --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || refuse
# Hooks run outside the agent sandbox here; refuse redirected hook directories.
if "${probe[@]}" config --get core.hooksPath >/dev/null 2>&1; then
  refuse
fi
# A temporary named remote keeps --force-with-lease tied to origin's
# tracking refs; refuse any other setting for that name.
[[ "$("${probe[@]}" config --name-only --get-regexp '^remote\.agentapp\.' 2>/dev/null)" == remote.agentapp.url ]] || refuse
# Local lefthook overrides can skip or replace the pre-push guard.
top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=.
for override in lefthook-local .lefthook-local .config/lefthook-local; do
  for extension in yml yaml toml json jsonc; do
    [[ ! -e "$top/$override.$extension" ]] || refuse
  done
done
if [[ "$subcmd" == push ]]; then
  # Implicit destinations follow the current branch; push.default is pinned below.
  implicit=true
  for refspec in ${refspecs[@]+"${refspecs[@]}"}; do
    [[ "$refspec" == HEAD || "$refspec" == @ ]] || implicit=false
  done
  if "$implicit" && [[ "$(git symbolic-ref --short -q HEAD 2>/dev/null)" == main ]]; then
    refuse
  fi
fi
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" != __AGENT_ORIGIN__ ]] || args[i]=agentapp
done
# Git shell helpers need shell quoting when the checkout path contains spaces.
printf -v helper '%q' "$SCRIPT_DIR/agent-git-credential.sh"
export AGENT_GIT_TOKEN="$token" AGENT_GIT_PATH="${repository}.git"
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false SSH_ASKPASS=/usr/bin/false
rc=0
git -c credential.helper= -c "credential.helper=!$helper" \
  -c credential.useHttpPath=true -c http.extraHeader= -c "http.$url.extraHeader=" \
  -c protocol.allow=never -c protocol.https.allow=always -c push.default=simple \
  -c "remote.agentapp.url=$url" -c 'remote.agentapp.fetch=+refs/heads/*:refs/remotes/origin/*' \
  "$subcmd" "${args[@]}" || rc=$?
unset AGENT_GIT_TOKEN
# push -u records the temporary remote; point tracking back at origin.
if [[ "$subcmd" == push ]]; then
  while read -r key value; do
    [[ "$value" != agentapp ]] || git config "$key" origin
  done < <(git config --local --get-regexp '^branch\..*\.remote$' 2>/dev/null || true)
fi
exit "$rc"
