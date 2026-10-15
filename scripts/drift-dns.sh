#!/usr/bin/env bash
# Local drift detection for infrastructure/dns.
#
# The dns module reads identifying configuration and API keys from production SOPS (GPG), which CI
# cannot (and must not) decrypt, so drift for this module is checked locally instead of in
# .github/workflows/drift-detection.yml.
#
# Output is limited to counts and resource addresses: no attribute values, no secrets.
# Exit codes: 0 = no drift, 2 = drift detected, 1 = error.
#
# Usage: scripts/drift-dns.sh [--module-dir DIR]
#   SOPS_FILE  overrides the credentials file (default: secrets/credentials.sops.yaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_DIR="$REPO_ROOT/infrastructure/dns"
SOPS_FILE="${SOPS_FILE:-$REPO_ROOT/secrets/credentials.sops.yaml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module-dir)
      MODULE_DIR="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

secret() { sops -d --extract "$1" "$SOPS_FILE"; }

# Redacts profile IDs, 32-hex IDs, email addresses, and loaded secret values from tool output.
mask() {
  local line
  while IFS= read -r line; do
    for s in "${SECRETS[@]}"; do
      [[ -n "$s" ]] && line="${line//"$s"/<redacted>}"
    done
    printf '%s\n' "$line" | sed -E 's/[0-9a-f]{32}/<id>/g; s/\b[0-9a-f]{6}\b/<profile_id>/g; s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g'
  done
}

CLOUDFLARE_ACCOUNT_ID="$(secret '["cloudflare"]["account_id"]')"
AWS_ACCESS_KEY_ID="$(secret '["opentofu"]["cloudflare_r2_access_key_id"]')"
AWS_SECRET_ACCESS_KEY="$(secret '["opentofu"]["cloudflare_r2_secret_access_key"]')"
TF_VAR_state_encryption_passphrase="$(secret '["opentofu"]["state_encryption_passphrase"]')"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_VAR_state_encryption_passphrase
export AWS_DEFAULT_REGION=auto

SECRETS=(
  "$CLOUDFLARE_ACCOUNT_ID"
  "$AWS_ACCESS_KEY_ID"
  "$AWS_SECRET_ACCESS_KEY"
  "$TF_VAR_state_encryption_passphrase"
)

for acct in account_1 account_2 account_3 account_4 account_5; do
  api_key="$(secret "[\"nextdns\"][\"accounts\"][\"${acct}\"][\"api_key\"]" 2>/dev/null || true)"
  account_name="$(secret "[\"nextdns\"][\"accounts\"][\"${acct}\"][\"account_name\"]" 2>/dev/null || true)"
  profile_id="$(secret "[\"nextdns\"][\"config\"][\"accounts\"][\"${acct}\"][\"profile_id\"]" 2>/dev/null || true)"
  profile_name="$(secret "[\"nextdns\"][\"config\"][\"accounts\"][\"${acct}\"][\"profile_name\"]" 2>/dev/null || true)"
  SECRETS+=("$api_key" "$profile_id" "$profile_name" "$account_name")
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

if ! tofu -chdir="$MODULE_DIR" init -input=false -reconfigure -lockfile=readonly \
  -backend-config="endpoint=https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com" \
  >"$WORK/init.log" 2>&1; then
  echo "init failed:" >&2
  grep -E 'Error' -A3 "$WORK/init.log" | mask >&2 || true
  exit 1
fi

set +e
tofu -chdir="$MODULE_DIR" plan -input=false -lock=false -detailed-exitcode -no-color \
  -out="$WORK/drift.plan" >"$WORK/plan.log" 2>&1
rc=$?
set -e

case "$rc" in
  0)
    echo "No drift: infrastructure/dns matches the configuration."
    exit 0
    ;;
  2)
    echo "DRIFT DETECTED in infrastructure/dns:"
    tofu -chdir="$MODULE_DIR" show -json "$WORK/drift.plan" | jq -r '
      [.resource_changes[] | select(.change.actions != ["no-op"])] as $c |
      "add: \([$c[] | select(.change.actions == ["create"])] | length)",
      "update: \([$c[] | select(.change.actions == ["update"])] | length)",
      "replace: \([$c[] | select(.change.actions | contains(["delete","create"]))] | length)",
      "destroy: \([$c[] | select(.change.actions == ["delete"])] | length)",
      ($c[] | "  \(.change.actions | join("+"))  \(.address)")' | mask
    exit 2
    ;;
  *)
    echo "plan failed (exit $rc):" >&2
    grep -E 'Error' -A3 "$WORK/plan.log" | mask >&2 || true
    exit 1
    ;;
esac
