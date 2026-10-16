#!/usr/bin/env bash
# Synchronize OpenTofu backup prune credentials and SOPS Restic passwords
# into the GitHub Actions 'ops' environment secrets for .github/workflows/backup-prune.yml.
#
# Usage:
#   scripts/sync-ops-secrets.sh [OPTIONS]
#
# Options:
#   --repo <owner/repo>       GitHub repository in 'owner/name' format (default: <sops github.owner>/infra)
#   --env <environment>       GitHub Actions environment name (default: ops)
#   --tofu-dir <dir>          Base infrastructure directory (default: <repo-root>/infrastructure)
#   --sops-file <file>        Path to canonical SOPS credentials file (default: secrets/credentials.sops.yaml)
#   --dry-run                 Preview secret names to be synchronized without calling gh or printing values
#   -h, --help                Display this help message and exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO=""
ENV_NAME="ops"
TOFU_DIR="$REPO_ROOT/infrastructure"
CREDENTIALS_FILE="${SOPS_FILE:-$REPO_ROOT/secrets/credentials.sops.yaml}"
DRY_RUN=false

usage() {
  sed -n '2,14p' "$0" | sed 's/^# *//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --env)
      ENV_NAME="$2"
      shift 2
      ;;
    --tofu-dir)
      TOFU_DIR="$2"
      shift 2
      ;;
    --sops-file)
      CREDENTIALS_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "ERROR: SOPS credentials file not found: $CREDENTIALS_FILE" >&2
  exit 1
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  if token="$(sops -d --extract '["github"]["token"]' "$CREDENTIALS_FILE" 2>/dev/null)" && [[ -n "$token" ]]; then
    export GH_TOKEN="$token"
  fi
fi

if [[ -z "$REPO" ]]; then
  if owner="$(sops -d --extract '["github"]["owner"]' "$CREDENTIALS_FILE" 2>/dev/null)" && [[ -n "$owner" ]]; then
    REPO="${owner}/infra"
  else
    echo "ERROR: Repository not specified and github.owner could not be extracted from SOPS." >&2
    exit 1
  fi
fi

if [[ ! "$REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Invalid repository format: '$REPO'. Must be 'owner/repo'." >&2
  exit 1
fi

extract_tofu_json() {
  local mod_dir="$1"
  if [[ ! -d "$mod_dir" ]]; then
    echo "ERROR: OpenTofu module directory not found: $mod_dir" >&2
    return 1
  fi
  tofu -chdir="$mod_dir" output -json
}

oci_json="$(extract_tofu_json "$TOFU_DIR/oci")"
gcp_json="$(extract_tofu_json "$TOFU_DIR/gcp")"
cf_json="$(extract_tofu_json "$TOFU_DIR/cloudflare")"

OCI_RESTIC_S3_ENDPOINT="$(jq -r '.backup_s3_endpoint.value // empty' <<<"$oci_json")"
OCI_RESTIC_BUCKET="$(jq -r '.backup_bucket_name.value // empty' <<<"$oci_json")"
OCI_RESTIC_PRUNE_ACCESS_KEY_ID="$(jq -r '.backup_prune_s3_access_key_id.value // empty' <<<"$oci_json")"
OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(jq -r '.backup_prune_s3_secret_access_key.value // empty' <<<"$oci_json")"
OCI_RESTIC_PASSWORD="$(sops -d --extract '["oci_restic"]["password"]' "$CREDENTIALS_FILE")"

GCP_RESTIC_S3_ENDPOINT="$(jq -r '.backup_s3_endpoint.value // empty' <<<"$gcp_json")"
GCP_RESTIC_BUCKET="$(jq -r '.backup_bucket_name.value // empty' <<<"$gcp_json")"
GCP_RESTIC_PRUNE_ACCESS_KEY_ID="$(jq -r '.backup_prune_hmac_access_id.value // empty' <<<"$gcp_json")"
GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(jq -r '.backup_prune_hmac_secret.value // empty' <<<"$gcp_json")"
GCP_RESTIC_PASSWORD="$(sops -d --extract '["gcp_restic"]["password"]' "$CREDENTIALS_FILE")"

R2_RESTIC_S3_ENDPOINT="$(jq -r '.r2_backup_endpoint.value // empty' <<<"$cf_json")"
R2_RESTIC_BUCKET="$(jq -r '.r2_backup_bucket_name.value // empty' <<<"$cf_json")"
R2_RESTIC_PRUNE_ACCESS_KEY_ID="$(jq -r '.r2_restic_prune_s3_access_key_id.value // empty' <<<"$cf_json")"
R2_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(jq -r '.r2_restic_prune_s3_secret_access_key.value // empty' <<<"$cf_json")"
R2_RESTIC_PASSWORD="$(sops -d --extract '["cloudflare_restic"]["password"]' "$CREDENTIALS_FILE")"

HEALTHCHECKS_BACKUP_PRUNE_PING_URL=""
if [[ -d "$TOFU_DIR/monitoring" ]]; then
  if mon_json="$(tofu -chdir="$TOFU_DIR/monitoring" output -json 2>/dev/null)"; then
    HEALTHCHECKS_BACKUP_PRUNE_PING_URL="$(jq -r '.backup_prune_ping_url.value // empty' <<<"$mon_json")"
  fi
fi

require_non_empty() {
  local name="$1"
  local val="$2"
  if [[ -z "$val" || "$val" == "null" ]]; then
    echo "ERROR: Required secret '$name' is empty or missing from OpenTofu outputs / SOPS." >&2
    exit 1
  fi
}

require_non_empty "OCI_RESTIC_S3_ENDPOINT" "$OCI_RESTIC_S3_ENDPOINT"
require_non_empty "OCI_RESTIC_BUCKET" "$OCI_RESTIC_BUCKET"
require_non_empty "OCI_RESTIC_PRUNE_ACCESS_KEY_ID" "$OCI_RESTIC_PRUNE_ACCESS_KEY_ID"
require_non_empty "OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY"
require_non_empty "OCI_RESTIC_PASSWORD" "$OCI_RESTIC_PASSWORD"
require_non_empty "GCP_RESTIC_S3_ENDPOINT" "$GCP_RESTIC_S3_ENDPOINT"
require_non_empty "GCP_RESTIC_BUCKET" "$GCP_RESTIC_BUCKET"
require_non_empty "GCP_RESTIC_PRUNE_ACCESS_KEY_ID" "$GCP_RESTIC_PRUNE_ACCESS_KEY_ID"
require_non_empty "GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY"
require_non_empty "GCP_RESTIC_PASSWORD" "$GCP_RESTIC_PASSWORD"
require_non_empty "R2_RESTIC_S3_ENDPOINT" "$R2_RESTIC_S3_ENDPOINT"
require_non_empty "R2_RESTIC_BUCKET" "$R2_RESTIC_BUCKET"
require_non_empty "R2_RESTIC_PRUNE_ACCESS_KEY_ID" "$R2_RESTIC_PRUNE_ACCESS_KEY_ID"
require_non_empty "R2_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$R2_RESTIC_PRUNE_SECRET_ACCESS_KEY"
require_non_empty "R2_RESTIC_PASSWORD" "$R2_RESTIC_PASSWORD"

sync_secret() {
  local name="$1"
  local val="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[%s] [DRY RUN] Would set secret %s in environment %s on %s\n' \
      "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$name" "$ENV_NAME" "$REPO"
  else
    printf '%s' "$val" | gh secret set "$name" --env "$ENV_NAME" --repo "$REPO"
    printf '[%s] [INFO] Synchronized secret %s in environment %s on %s\n' \
      "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$name" "$ENV_NAME" "$REPO"
  fi
}

sync_secret "OCI_RESTIC_S3_ENDPOINT" "$OCI_RESTIC_S3_ENDPOINT"
sync_secret "OCI_RESTIC_BUCKET" "$OCI_RESTIC_BUCKET"
sync_secret "OCI_RESTIC_PRUNE_ACCESS_KEY_ID" "$OCI_RESTIC_PRUNE_ACCESS_KEY_ID"
sync_secret "OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY"
sync_secret "OCI_RESTIC_PASSWORD" "$OCI_RESTIC_PASSWORD"
sync_secret "GCP_RESTIC_S3_ENDPOINT" "$GCP_RESTIC_S3_ENDPOINT"
sync_secret "GCP_RESTIC_BUCKET" "$GCP_RESTIC_BUCKET"
sync_secret "GCP_RESTIC_PRUNE_ACCESS_KEY_ID" "$GCP_RESTIC_PRUNE_ACCESS_KEY_ID"
sync_secret "GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY"
sync_secret "GCP_RESTIC_PASSWORD" "$GCP_RESTIC_PASSWORD"
sync_secret "R2_RESTIC_S3_ENDPOINT" "$R2_RESTIC_S3_ENDPOINT"
sync_secret "R2_RESTIC_BUCKET" "$R2_RESTIC_BUCKET"
sync_secret "R2_RESTIC_PRUNE_ACCESS_KEY_ID" "$R2_RESTIC_PRUNE_ACCESS_KEY_ID"
sync_secret "R2_RESTIC_PRUNE_SECRET_ACCESS_KEY" "$R2_RESTIC_PRUNE_SECRET_ACCESS_KEY"
sync_secret "R2_RESTIC_PASSWORD" "$R2_RESTIC_PASSWORD"

if [[ -n "$HEALTHCHECKS_BACKUP_PRUNE_PING_URL" && "$HEALTHCHECKS_BACKUP_PRUNE_PING_URL" != "null" ]]; then
  sync_secret "HEALTHCHECKS_BACKUP_PRUNE_PING_URL" "$HEALTHCHECKS_BACKUP_PRUNE_PING_URL"
fi
