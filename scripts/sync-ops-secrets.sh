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
#   --dry-run                 Validate inputs and list secret names without calling gh or printing values
#   -h, --help                Display this help message and exit

# Secret variables are read through ${!name} indirection over SECRET_NAMES.
# shellcheck disable=SC2034
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

require_arg() {
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    echo "ERROR: $1 requires a value." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      require_arg "$@"
      REPO="$2"
      shift 2
      ;;
    --env)
      require_arg "$@"
      ENV_NAME="$2"
      shift 2
      ;;
    --tofu-dir)
      require_arg "$@"
      TOFU_DIR="$2"
      shift 2
      ;;
    --sops-file)
      require_arg "$@"
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

if [[ ! "$ENV_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Invalid environment name: '$ENV_NAME'." >&2
  exit 1
fi

# Prune-capable keys, endpoints, buckets and the prune heartbeat URL (fails closed).
prune_json="$("$SCRIPT_DIR/get-tofu-restic-vars.sh" --mode prune --tofu-dir "$TOFU_DIR" --sops-file "$CREDENTIALS_FILE")"

field() { printf '%s' "$prune_json" | jq -r "$1 // empty"; }

OCI_RESTIC_S3_ENDPOINT="$(field '.tofu_oci_restic.s3_endpoint')"
OCI_RESTIC_BUCKET="$(field '.tofu_oci_restic.bucket')"
OCI_RESTIC_PRUNE_ACCESS_KEY_ID="$(field '.tofu_oci_restic.s3_access_key_id')"
OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(field '.tofu_oci_restic.s3_secret_access_key')"
OCI_RESTIC_PASSWORD="$(sops -d --extract '["oci_restic"]["password"]' "$CREDENTIALS_FILE")"

GCP_RESTIC_S3_ENDPOINT="$(field '.tofu_gcp_restic.s3_endpoint')"
GCP_RESTIC_BUCKET="$(field '.tofu_gcp_restic.bucket')"
GCP_RESTIC_PRUNE_ACCESS_KEY_ID="$(field '.tofu_gcp_restic.s3_access_key_id')"
GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(field '.tofu_gcp_restic.s3_secret_access_key')"
GCP_RESTIC_PASSWORD="$(sops -d --extract '["gcp_restic"]["password"]' "$CREDENTIALS_FILE")"

R2_RESTIC_S3_ENDPOINT="$(field '.tofu_cloudflare_restic.s3_endpoint')"
R2_RESTIC_BUCKET="$(field '.tofu_cloudflare_restic.bucket')"
R2_RESTIC_PRUNE_ACCESS_KEY_ID="$(field '.tofu_cloudflare_restic.s3_access_key_id')"
R2_RESTIC_PRUNE_SECRET_ACCESS_KEY="$(field '.tofu_cloudflare_restic.s3_secret_access_key')"
R2_RESTIC_PASSWORD="$(sops -d --extract '["cloudflare_restic"]["password"]' "$CREDENTIALS_FILE")"

HEALTHCHECKS_BACKUP_PRUNE_PING_URL="$(field '.backup_prune_ping_url')"

SECRET_NAMES=(
  OCI_RESTIC_S3_ENDPOINT OCI_RESTIC_BUCKET OCI_RESTIC_PRUNE_ACCESS_KEY_ID OCI_RESTIC_PRUNE_SECRET_ACCESS_KEY OCI_RESTIC_PASSWORD
  GCP_RESTIC_S3_ENDPOINT GCP_RESTIC_BUCKET GCP_RESTIC_PRUNE_ACCESS_KEY_ID GCP_RESTIC_PRUNE_SECRET_ACCESS_KEY GCP_RESTIC_PASSWORD
  R2_RESTIC_S3_ENDPOINT R2_RESTIC_BUCKET R2_RESTIC_PRUNE_ACCESS_KEY_ID R2_RESTIC_PRUNE_SECRET_ACCESS_KEY R2_RESTIC_PASSWORD
  HEALTHCHECKS_BACKUP_PRUNE_PING_URL
)

# Validate everything before the first write so a failure never leaves a partial sync.
for name in "${SECRET_NAMES[@]}"; do
  if [[ -z "${!name}" || "${!name}" == "null" ]]; then
    echo "ERROR: Required secret '$name' is empty or missing from OpenTofu outputs / SOPS." >&2
    exit 1
  fi
done

if [[ "$DRY_RUN" != "true" && -z "${GH_TOKEN:-}" ]]; then
  if token="$(sops -d --extract '["github"]["token"]' "$CREDENTIALS_FILE" 2>/dev/null)" && [[ -n "$token" ]]; then
    export GH_TOKEN="$token"
  fi
fi

for name in "${SECRET_NAMES[@]}"; do
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[%s] [DRY RUN] Would set secret %s in environment %s on %s\n' \
      "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$name" "$ENV_NAME" "$REPO"
  else
    printf '%s' "${!name}" | gh secret set "$name" --env "$ENV_NAME" --repo "$REPO"
    printf '[%s] [INFO] Synchronized secret %s in environment %s on %s\n' \
      "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$name" "$ENV_NAME" "$REPO"
  fi
done
