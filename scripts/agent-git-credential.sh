#!/usr/bin/env bash
# Git credential protocol endpoint. Token is supplied only in the child env.
set +x
set -euo pipefail
[[ -n "${AGENT_GIT_TOKEN:-}" ]] || exit 1
case "${1:-}" in
  store | erase) exit 0 ;;
  get) ;;
  *) exit 1 ;;
esac
protocol='' host='' path=''
while IFS='=' read -r key value && [[ -n "$key" ]]; do
  case "$key" in
    protocol) protocol="$value" ;;
    host) host="$value" ;;
    path) path="$value" ;;
  esac
done
[[ "$protocol" == https && "$host" == github.com ]] || exit 1
[[ -n "${AGENT_GIT_PATH:-}" && "$path" == "$AGENT_GIT_PATH" ]] || exit 1
printf 'username=x-access-token\npassword=%s\n' "$AGENT_GIT_TOKEN"
