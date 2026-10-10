#!/usr/bin/env bash
# Synchronize Cloudflare live account billing budget alert (billing_budget_alert)
# to the platform minimum threshold ($1 USD or specified threshold).
#
# Usage:
#   scripts/sync-cloudflare-budget-alert.sh [OPTIONS]
#
# Options:
#   --threshold <dollars>         Monthly spend threshold in USD (positive integer, default: 1)
#   --dry-run                     Preview planned alert configuration without making API requests
#   --credentials-file <file>     Path to canonical SOPS credentials file (default: secrets/credentials.sops.yaml)
#   --token <token>               Cloudflare API Token (default: auto-detected from SOPS)
#   --account-id <id>             Cloudflare Account ID (default: auto-detected from SOPS)
#   --email <email>               Notification email address (default: auto-detected from SOPS)
#   -h, --help                    Display this help message and exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure mise tools are available on PATH if not already present
if ! command -v sops >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  if [[ -d "${HOME}/.local/share/mise/bin" ]]; then
    export PATH="${HOME}/.local/share/mise/bin:${PATH}"
  fi
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise env --shell bash 2>/dev/null || true)"
  fi
fi

# Default parameter values
THRESHOLD="1"
DRY_RUN=false
CREDENTIALS_FILE="${SOPS_FILE:-$REPO_ROOT/secrets/credentials.sops.yaml}"
TOKEN=""
ACCOUNT_ID=""
EMAIL=""

usage() {
  sed -n '2,14p' "$0" | sed 's/^# *//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      THRESHOLD="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --credentials-file)
      CREDENTIALS_FILE="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --account-id)
      ACCOUNT_ID="${2:-}"
      shift 2
      ;;
    --email)
      EMAIL="${2:-}"
      shift 2
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

# Validate threshold (must be positive integer >= 1)
if ! [[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: Invalid threshold: '$THRESHOLD'. Must be a positive integer >= 1." >&2
  exit 1
fi

# Resolve credentials and account details from SOPS if not provided explicitly
if [[ -z "$TOKEN" || -z "$ACCOUNT_ID" || -z "$EMAIL" ]]; then
  if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    if [[ -f "$REPO_ROOT/secrets/credentials.ci.sops.yaml" ]]; then
      CREDENTIALS_FILE="$REPO_ROOT/secrets/credentials.ci.sops.yaml"
    else
      echo "ERROR: Credentials file not found: $CREDENTIALS_FILE" >&2
      exit 1
    fi
  fi

  if [[ -z "$TOKEN" ]]; then
    if ! TOKEN="$(sops --extract '["cloudflare"]["api_token"]' "$CREDENTIALS_FILE" 2>/dev/null)"; then
      echo "ERROR: Failed to extract Cloudflare credentials from SOPS: $CREDENTIALS_FILE" >&2
      exit 1
    fi
  fi

  if [[ -z "$ACCOUNT_ID" ]]; then
    if ! ACCOUNT_ID="$(sops --extract '["cloudflare"]["account_id"]' "$CREDENTIALS_FILE" 2>/dev/null)"; then
      echo "ERROR: Failed to extract Cloudflare credentials from SOPS: $CREDENTIALS_FILE" >&2
      exit 1
    fi
  fi

  if [[ -z "$EMAIL" ]]; then
    if ! EMAIL="$(sops --extract '["cloudflare"]["config"]["notification_email"]' "$CREDENTIALS_FILE" 2>/dev/null)"; then
      if ! EMAIL="$(sops --extract '["cloudflare"]["notification_email"]' "$CREDENTIALS_FILE" 2>/dev/null)"; then
        echo "ERROR: Failed to extract Cloudflare credentials from SOPS: $CREDENTIALS_FILE" >&2
        exit 1
      fi
    fi
  fi
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

API_BASE="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/alerting/v3/policies"

# Query existing alerting policies
POLICIES_RESPONSE=$(curl -sS \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${API_BASE}") || {
  echo "ERROR: Failed to query Cloudflare alerting policies" >&2
  exit 1
}

if ! echo "$POLICIES_RESPONSE" | jq -e '.success == true' >/dev/null 2>&1; then
  ERR_MSG=$(echo "$POLICIES_RESPONSE" | jq -c '.errors // []' 2>/dev/null || echo "Unknown error")
  echo "ERROR: Cloudflare API returned failure querying alerting policies: $ERR_MSG" >&2
  exit 1
fi

EXISTING_POLICY=$(echo "$POLICIES_RESPONSE" | jq -c '.result[] | select(.alert_type == "billing_budget_alert")' | head -n 1)

if [[ -n "$EXISTING_POLICY" ]]; then
  POLICY_ID=$(echo "$EXISTING_POLICY" | jq -r '.id')
  CURRENT_THRESHOLD=$(echo "$EXISTING_POLICY" | jq -r '.filters.total_spend_dollars[0] // empty')
  CURRENT_ENABLED=$(echo "$EXISTING_POLICY" | jq -r '.enabled')

  if [[ "$CURRENT_THRESHOLD" == "$THRESHOLD" && "$CURRENT_ENABLED" == "true" ]]; then
    log_info "Cloudflare billing_budget_alert already set to \$${THRESHOLD} USD and enabled (policy ID: ${POLICY_ID}). No changes needed."
    exit 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would update Cloudflare billing_budget_alert (policy ID: ${POLICY_ID}) threshold to \$${THRESHOLD} USD (current: \$${CURRENT_THRESHOLD:-unset})."
    exit 0
  fi

  EXISTING_MECHANISMS=$(echo "$EXISTING_POLICY" | jq -c '.mechanisms // empty')
  if [[ -n "$EXISTING_MECHANISMS" && "$EXISTING_MECHANISMS" != "null" && "$EXISTING_MECHANISMS" != "{}" ]]; then
    MECHANISMS="$EXISTING_MECHANISMS"
  else
    MECHANISMS=$(jq -n --arg email "$EMAIL" '{"email": [{"id": $email}]}')
  fi

  PAYLOAD=$(jq -n -c \
    --arg name "Billing Budget Alert" \
    --arg desc "Billing budget alert triggered when monthly spend exceeds threshold" \
    --argjson mechanisms "$MECHANISMS" \
    --arg threshold "$THRESHOLD" \
    '{
      name: $name,
      description: $desc,
      alert_type: "billing_budget_alert",
      enabled: true,
      mechanisms: $mechanisms,
      filters: {
        total_spend_dollars: [$threshold]
      }
    }')

  UPDATE_RESPONSE=$(curl -sS -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${API_BASE}/${POLICY_ID}")

  if ! echo "$UPDATE_RESPONSE" | jq -e '.success == true' >/dev/null 2>&1; then
    ERR_MSG=$(echo "$UPDATE_RESPONSE" | jq -c '.errors // []' 2>/dev/null || echo "Unknown error")
    echo "ERROR: Failed to update Cloudflare billing_budget_alert: $ERR_MSG" >&2
    exit 1
  fi

  log_info "Updated Cloudflare billing_budget_alert (policy ID: ${POLICY_ID}) threshold to \$${THRESHOLD} USD."
  exit 0
else
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would create Cloudflare billing_budget_alert with threshold \$${THRESHOLD} USD for email ${EMAIL}."
    exit 0
  fi

  PAYLOAD=$(jq -n -c \
    --arg name "Billing Budget Alert" \
    --arg desc "Billing budget alert triggered when monthly spend exceeds threshold" \
    --arg email "$EMAIL" \
    --arg threshold "$THRESHOLD" \
    '{
      name: $name,
      description: $desc,
      alert_type: "billing_budget_alert",
      enabled: true,
      mechanisms: {
        email: [{id: $email}]
      },
      filters: {
        total_spend_dollars: [$threshold]
      }
    }')

  CREATE_RESPONSE=$(curl -sS -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${API_BASE}")

  if ! echo "$CREATE_RESPONSE" | jq -e '.success == true' >/dev/null 2>&1; then
    ERR_MSG=$(echo "$CREATE_RESPONSE" | jq -c '.errors // []' 2>/dev/null || echo "Unknown error")
    echo "ERROR: Failed to create Cloudflare billing_budget_alert: $ERR_MSG" >&2
    exit 1
  fi

  NEW_ID=$(echo "$CREATE_RESPONSE" | jq -r 'if (.result | type) == "object" then .result.id else (.result[0].id // "created") end // "created"' 2>/dev/null || echo "created")
  log_info "Created Cloudflare billing_budget_alert (policy ID: ${NEW_ID}) with threshold \$${THRESHOLD} USD."
  exit 0
fi
