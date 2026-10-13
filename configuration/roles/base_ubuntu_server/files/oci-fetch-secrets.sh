#!/usr/bin/env bash
# Managed by Ansible - homelab infrastructure
# Fetches secret bundles from OCI Vault into in-memory tmpfs (/run/secrets/)
# using Instance Principals via IMDSv2.
set -euo pipefail

DEST_DIR="${SECRETS_DEST_DIR:-/run/secrets}"
VAULT_ID="${OCI_VAULT_ID:-}"
DRY_RUN=false
MAX_RETRIES="${OCI_MAX_RETRIES:-3}"
RETRY_DELAY="${OCI_RETRY_DELAY:-1}"
SECRETS=()

usage() {
  cat <<'EOF'
Usage: oci-fetch-secrets.sh [OPTIONS] [SECRET_NAMES...]

Fetches secret bundles from OCI Vault into in-memory tmpfs (/run/secrets/)
using Instance Principals via IMDSv2.

Options:
  --dest DIR             Destination directory (default: /run/secrets or $SECRETS_DEST_DIR)
  --vault-id OCID        OCI Vault OCID (default: $OCI_VAULT_ID)
  --dry-run              Validate configuration and directories without calling OCI API
  --max-retries N        Maximum retry attempts for fetching secrets (default: 3)
  --retry-delay SECS     Initial delay between retries in seconds (default: 1)
  -h, --help             Show this help message
EOF
  exit 0
}

decode_base64() {
  if command -v base64 >/dev/null 2>&1; then
    base64 -d
  elif command -v openssl >/dev/null 2>&1; then
    openssl base64 -d -A
  else
    echo "Error: No base64 decoder available" >&2
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || {
        echo "Error: --dest requires an argument" >&2
        exit 1
      }
      DEST_DIR="$2"
      shift 2
      ;;
    --vault-id)
      [[ $# -ge 2 ]] || {
        echo "Error: --vault-id requires an argument" >&2
        exit 1
      }
      VAULT_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --max-retries)
      [[ $# -ge 2 ]] || {
        echo "Error: --max-retries requires an argument" >&2
        exit 1
      }
      MAX_RETRIES="$2"
      shift 2
      ;;
    --retry-delay)
      [[ $# -ge 2 ]] || {
        echo "Error: --retry-delay requires an argument" >&2
        exit 1
      }
      RETRY_DELAY="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        SECRETS+=("$1")
        shift
      done
      break
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      SECRETS+=("$1")
      shift
      ;;
  esac
done

# Ensure destination directory exists strictly with 0700 permissions
mkdir -p "$DEST_DIR"
chmod 0700 "$DEST_DIR"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry-run validation successful. Destination directory: $DEST_DIR (mode 0700)"
  exit 0
fi

if ! command -v oci >/dev/null 2>&1; then
  echo "Error: 'oci' CLI executable not found in PATH" >&2
  exit 1
fi

if [[ -z "$VAULT_ID" ]]; then
  echo "Error: OCI Vault ID is required. Pass --vault-id <OCID> or set OCI_VAULT_ID." >&2
  exit 1
fi

DEFAULT_SECRETS=(
  "restic_password"
  "restic_secondary_password"
  "oci_s3_secret_key"
  "cloudflare_s3_secret_key"
  "healthchecks_ping_url"
)

if [[ ${#SECRETS[@]} -eq 0 ]]; then
  SECRETS=("${DEFAULT_SECRETS[@]}")
fi

fetch_secret() {
  local secret_name="$1"
  local dest_file="${DEST_DIR}/${secret_name}"
  local attempt=1
  local raw_base64=""
  local fetch_success=false

  while [[ "$attempt" -le "$MAX_RETRIES" ]]; do
    if raw_base64=$(oci secrets secret-bundle get-secret-bundle-by-name \
      --vault-id "$VAULT_ID" \
      --secret-name "$secret_name" \
      --auth instance_principal \
      --query 'data."secret-bundle-content".content' \
      --raw-output 2>/dev/null); then
      if [[ -n "$raw_base64" && "$raw_base64" != "null" ]]; then
        fetch_success=true
        break
      fi
    fi

    echo "Attempt $attempt of $MAX_RETRIES failed to fetch secret '${secret_name}'. Retrying in ${RETRY_DELAY}s..." >&2
    sleep "$RETRY_DELAY"
    attempt=$((attempt + 1))
  done

  if [[ "$fetch_success" != true ]]; then
    echo "Error: Failed to fetch secret '${secret_name}' after ${MAX_RETRIES} attempts" >&2
    rm -f "$dest_file"
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp "${DEST_DIR}/.${secret_name}.tmp.XXXXXX")
  chmod 0600 "$tmp_file"

  if ! printf '%s' "$raw_base64" | decode_base64 >"$tmp_file"; then
    echo "Error: Failed to decode base64 content for secret '${secret_name}'" >&2
    rm -f "$tmp_file"
    return 1
  fi

  chmod 0400 "$tmp_file"
  mv -f "$tmp_file" "$dest_file"
  return 0
}

for secret in "${SECRETS[@]}"; do
  if ! fetch_secret "$secret"; then
    echo "Error: Aborting due to failure fetching secret '${secret}'" >&2
    exit 1
  fi
done
