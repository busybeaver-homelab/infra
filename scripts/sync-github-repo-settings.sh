#!/usr/bin/env bash
# Synchronize GitHub repository settings not managed directly via OpenTofu resources:
# - Immutable Releases (PUT /repos/:owner/:repo/immutable-releases)
# - Actions Artifact & Log Retention to 14 days (PUT /repos/:owner/:repo/actions/permissions/artifact-and-log-retention)
# - Fork PR Contributor Approval to all_external_contributors (PUT /repos/:owner/:repo/actions/permissions/fork-pr-contributor-approval)
# - Vulnerability Alerts & Dependency Graph (PUT /repos/:owner/:repo/vulnerability-alerts)
# - Secret Scanning & Push Protection (PATCH /repos/:owner/:repo)
#
# Usage:
#   scripts/sync-github-repo-settings.sh [OPTIONS]
#
# Options:
#   --repo <owner/repo>           GitHub repository in 'owner/name' format (default: auto-detected from SOPS)
#   --token <token>               GitHub Personal Access Token (default: auto-detected from SOPS)
#   --credentials-file <file>     Path to canonical SOPS credentials file (default: secrets/credentials.sops.yaml)
#   --dry-run                     Preview planned settings updates without making API requests
#   -h, --help                    Display this help message and exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default parameter values
REPO=""
TOKEN=""
CREDENTIALS_FILE="${SOPS_FILE:-$REPO_ROOT/secrets/credentials.sops.yaml}"
DRY_RUN=false

usage() {
  sed -n '2,16p' "$0" | sed 's/^# *//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --credentials-file)
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
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve credentials and repository from SOPS if not provided explicitly
if [[ -z "$TOKEN" ]]; then
  if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    # Fallback to CI credentials file if production file is not present
    if [[ -f "$REPO_ROOT/secrets/credentials.ci.sops.yaml" ]]; then
      CREDENTIALS_FILE="$REPO_ROOT/secrets/credentials.ci.sops.yaml"
    else
      echo "ERROR: Credentials file not found: $CREDENTIALS_FILE" >&2
      exit 1
    fi
  fi

  if ! TOKEN="$(sops -d --extract '["github"]["token"]' "$CREDENTIALS_FILE" 2>/dev/null)"; then
    echo "ERROR: Failed to extract GitHub token from SOPS: $CREDENTIALS_FILE" >&2
    exit 1
  fi
fi

if [[ -z "$REPO" ]]; then
  if OWNER="$(sops -d --extract '["github"]["owner"]' "$CREDENTIALS_FILE" 2>/dev/null)" && [[ -n "$OWNER" ]]; then
    REPO="${OWNER}/infra"
  else
    echo "ERROR: Repository not specified and owner could not be determined from SOPS." >&2
    exit 1
  fi
fi

# Validate repository format (owner/repo)
if [[ ! "$REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Invalid repository format: '$REPO'. Must be 'owner/repo'." >&2
  exit 1
fi

mask_token() {
  local input="$1"
  if [[ -n "$TOKEN" ]]; then
    printf '%s\n' "${input//$TOKEN/<redacted>}"
  else
    printf '%s\n' "$input"
  fi
}

log_info() {
  local msg="$1"
  local masked
  masked="$(mask_token "$msg")"
  printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$masked"
}

log_dry_run() {
  local msg="$1"
  local masked
  masked="$(mask_token "$msg")"
  printf '[%s] [DRY RUN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$masked"
}

API_BASE="https://api.github.com"
API_VERSION="2022-11-28"

call_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local url="${API_BASE}${endpoint}"
  log_info "Calling ${method} ${endpoint}..."

  local curl_args=(
    -sS
    -X "$method"
    -H "Accept: application/vnd.github+json"
    -H "Authorization: Bearer ${TOKEN}"
    -H "X-GitHub-Api-Version: ${API_VERSION}"
  )

  if [[ -n "$data" ]]; then
    curl_args+=(-H "Content-Type: application/json" -d "$data")
  fi

  curl "${curl_args[@]}" "$url" >/dev/null
  log_info "Response received for ${endpoint}"
}

if [[ "$DRY_RUN" == true ]]; then
  log_dry_run "Syncing repository settings for ${REPO}"
  log_dry_run "Would PUT /repos/${REPO}/immutable-releases"
  log_dry_run "Would PUT /repos/${REPO}/actions/permissions/artifact-and-log-retention with {'days': 14}"
  log_dry_run "Would PUT /repos/${REPO}/actions/permissions/fork-pr-contributor-approval with {'approval_policy': 'all_external_contributors'}"
  log_dry_run "Would PUT /repos/${REPO}/vulnerability-alerts"
  log_dry_run "Would PATCH /repos/${REPO} with secret scanning and push protection enabled"
  exit 0
fi

log_info "Starting GitHub repository settings sync for ${REPO}..."

# 1. Enable Release Immutability
log_info "Configuring Release Immutability..."
call_api "PUT" "/repos/${REPO}/immutable-releases"

# 2. Configure Actions Artifact and Log Retention to 14 days
log_info "Configuring Actions Artifact and Log Retention to 14 days..."
call_api "PUT" "/repos/${REPO}/actions/permissions/artifact-and-log-retention" '{"days":14}'

# 3. Configure Fork PR Contributor Approval Policy to all_external_contributors
log_info "Configuring Fork PR Contributor Approval Policy..."
call_api "PUT" "/repos/${REPO}/actions/permissions/fork-pr-contributor-approval" '{"approval_policy":"all_external_contributors"}'

# 4. Enable Vulnerability Alerts & Dependency Graph
log_info "Enabling Vulnerability Alerts & Dependency Graph..."
call_api "PUT" "/repos/${REPO}/vulnerability-alerts"

# 5. Enable Secret Scanning & Push Protection
log_info "Enabling Secret Scanning & Push Protection..."
call_api "PATCH" "/repos/${REPO}" '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'

log_info "GitHub repository settings successfully synchronized for ${REPO}."
