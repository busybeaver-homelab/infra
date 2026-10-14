#!/usr/bin/env bash
# Operator wrapper for running OpenTofu commands in infrastructure/dns with
# R2 backend credentials and PBKDF2 state encryption passphrase sourced from SOPS.
#
# Usage: scripts/tofu-dns.sh <tofu-subcommand> [args...]
#   SOPS_FILE  overrides the credentials file (default: secrets/credentials.sops.yaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_DIR="${MODULE_DIR:-$REPO_ROOT/infrastructure/dns}"
SOPS_FILE="${SOPS_FILE:-$REPO_ROOT/secrets/credentials.sops.yaml}"

if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  sed -n '2,6p' "$0"
  exit 0
fi

secret() { sops -d --extract "$1" "$SOPS_FILE"; }

CLOUDFLARE_ACCOUNT_ID="$(secret '["cloudflare"]["account_id"]')"
AWS_ACCESS_KEY_ID="$(secret '["opentofu"]["cloudflare_r2_access_key_id"]')"
AWS_SECRET_ACCESS_KEY="$(secret '["opentofu"]["cloudflare_r2_secret_access_key"]')"
TF_VAR_state_encryption_passphrase="$(secret '["opentofu"]["state_encryption_passphrase"]')"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_state_encryption_passphrase
export AWS_DEFAULT_REGION=auto

subcmd="$1"
shift

if [[ "$subcmd" == "init" ]]; then
  lock_flag="-lockfile=readonly"
  for arg in "$@"; do
    if [[ "$arg" == "-upgrade" ]] || [[ "$arg" == -lockfile=* ]]; then
      lock_flag=""
    fi
  done
  if [[ -n "$lock_flag" ]]; then
    exec tofu -chdir="$MODULE_DIR" init "$lock_flag" \
      -backend-config="endpoint=https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com" \
      "$@"
  else
    exec tofu -chdir="$MODULE_DIR" init \
      -backend-config="endpoint=https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com" \
      "$@"
  fi
fi

exec tofu -chdir="$MODULE_DIR" "$subcmd" "$@"
