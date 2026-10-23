#!/usr/bin/env bash
# Sourced library: mint short-lived GitHub App installation tokens for AI agents.
#
# The app private key and app metadata live in the SOPS-encrypted credentials
# file. The private key only ever travels through pipes (sops -> openssl); it is
# never held in a variable, written to disk, or placed on any argv. The JWT and
# the installation token are passed to curl as a stdin config (never argv).
#
# Functions:
#   github_app_mint_token   print an installation token on stdout (capture with $(...))
#   github_app_identity     print "name<TAB>email" for the app's bot user
#
# Environment:
#   GITHUB_APP_SOPS_FILE    default: <repo>/secrets/credentials.sops.yaml
#   GITHUB_API_URL          default: https://api.github.com
#   GITHUB_APP_REPOSITORY   default: infra
#
# Exit codes: 3 missing/undecryptable SOPS value, 4 JWT/openssl failure,
#             5 HTTP/JSON failure.
#
# This file must not set shell options on source; functions run in subshells.

_GITHUB_APP_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

_github_app_err() {
  printf 'ERROR: %s\n' "$*" >&2
}

# Read one non-empty value from SOPS; exit 3 with a hint when unavailable.
_github_app_sops_value() {
  local path="$1" file="${GITHUB_APP_SOPS_FILE:-$_GITHUB_APP_REPO_ROOT/secrets/credentials.sops.yaml}" value
  if ! value="$(sops -d --extract "$path" "$file" 2>/dev/null)" || [[ -z "$value" ]]; then
    _github_app_err "cannot read ${path} from SOPS; check GPG key availability (scripts/check-gpg-expiry.sh)"
    return 3
  fi
  printf '%s' "$value"
}

_github_app_b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

github_app_mint_token() (
  set -o pipefail
  local cfg='["github"]["config"]["agent_app"]'
  local key_path='["github"]["agent_app"]["private_key"]'
  local file="${GITHUB_APP_SOPS_FILE:-$_GITHUB_APP_REPO_ROOT/secrets/credentials.sops.yaml}"
  local api="${GITHUB_API_URL:-https://api.github.com}"
  local repo="${GITHUB_APP_REPOSITORY:-infra}"
  local app_id installation_id rc

  app_id="$(_github_app_sops_value "${cfg}[\"app_id\"]")" || exit 3
  installation_id="$(_github_app_sops_value "${cfg}[\"installation_id\"]")" || exit 3

  local work
  work="$(mktemp -d)" || {
    _github_app_err "cannot create temporary directory"
    exit 4
  }
  trap 'rm -rf "$work"' EXIT

  # JWT: header.payload is non-secret and goes through a file removed on exit.
  local now header payload input signature
  now="$(date +%s)"
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | _github_app_b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$app_id" | _github_app_b64url)"
  input="${header}.${payload}"
  printf '%s' "$input" >"$work/input"

  # The private key flows sops -> openssl through a pipe only.
  local -a status
  sops -d --extract "$key_path" "$file" 2>/dev/null |
    openssl dgst -sha256 -sign /dev/stdin -out "$work/sig" "$work/input" 2>/dev/null
  status=("${PIPESTATUS[@]}")
  if [[ "${status[0]}" -ne 0 ]]; then
    _github_app_err "cannot read ${key_path} from SOPS; check GPG key availability (scripts/check-gpg-expiry.sh)"
    exit 3
  fi
  if [[ "${status[1]}" -ne 0 || ! -s "$work/sig" ]]; then
    _github_app_err "failed to sign GitHub App JWT with openssl"
    exit 4
  fi
  signature="$(_github_app_b64url <"$work/sig")" || {
    _github_app_err "failed to encode GitHub App JWT signature"
    exit 4
  }

  local body response token
  body="$(jq -cn --arg repo "$repo" '{
    repositories: [$repo],
    permissions: {
      contents: "write", pull_requests: "write", workflows: "write",
      checks: "read", statuses: "read", actions: "read",
      security_events: "read", metadata: "read"
    }
  }')" || {
    _github_app_err "failed to build token request body"
    exit 5
  }

  # Authorization travels on a stdin curl config; the response body is never echoed.
  rc=0
  response="$(
    printf 'header = "Authorization: Bearer %s"\n' "${input}.${signature}" |
      curl -sS --fail-with-body -K - -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "$body" \
        "${api}/app/installations/${installation_id}/access_tokens" 2>/dev/null
  )" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _github_app_err "GitHub installation token request failed (curl exit ${rc})"
    exit 5
  fi
  token="$(jq -r '.token // empty' <<<"$response" 2>/dev/null)" || token=""
  if [[ -z "$token" ]]; then
    _github_app_err "GitHub response did not contain an installation token"
    exit 5
  fi
  printf '%s\n' "$token"
)

github_app_identity() (
  local cfg='["github"]["config"]["agent_app"]'
  local slug bot_id
  slug="$(_github_app_sops_value "${cfg}[\"slug\"]")" || exit 3
  bot_id="$(_github_app_sops_value "${cfg}[\"bot_user_id\"]")" || exit 3
  printf '%s[bot]\t%s+%s[bot]@users.noreply.github.com\n' "$slug" "$bot_id" "$slug"
)
