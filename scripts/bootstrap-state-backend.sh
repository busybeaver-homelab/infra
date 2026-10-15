#!/usr/bin/env bash

# Homelab OpenTofu State Backend Bootstrap Script (Pattern A)
#
# Implements Pattern A: Two-Stage Local-to-Remote State Migration for Cloudflare R2
#
# Stage 1: Disables remote backend in infrastructure/cloudflare, initializes local state,
#          and creates the R2 state bucket (cloudflare_r2_bucket.tfstate) via targeted apply.
# Stage 2: Restores remote backend configuration in infrastructure/cloudflare, and runs
#          tofu init -migrate-state -force-copy to migrate state to Cloudflare R2.

set -Eeuo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Structured logging
log_info() {
  printf "${GREEN}[INFO]${NC} %s\n" "$*"
}

log_warn() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

log_error() {
  printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_step() {
  printf "${BLUE}[STEP]${NC} %s\n" "$*"
}

# Defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_MODULE_DIR="${REPO_ROOT}/infrastructure/cloudflare"
MODULE_DIR="${DEFAULT_MODULE_DIR}"
BUCKET_NAME="homelab-infra-tfstate"
STAGE="all"
ENV_TARGET="prod"
DRY_RUN=false
AUTO_APPROVE=false

BACKEND_FILE=""
BACKEND_BACKUP=""
BACKEND_MOVED=false

cleanup() {
  local exit_code=$?
  if [[ "${BACKEND_MOVED}" == "true" && -n "${BACKEND_BACKUP}" && -f "${BACKEND_BACKUP}" && ! -f "${BACKEND_FILE}" ]]; then
    log_warn "Restoring ${BACKEND_FILE} due to abnormal termination or error..."
    mv "${BACKEND_BACKUP}" "${BACKEND_FILE}" || true
  fi
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM ERR

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automate OpenTofu remote state bootstrap using Pattern A (Two-Stage Local-to-Remote State Migration).

Pattern A Workflow:
  Stage 1: Disables remote backend in infrastructure/cloudflare, initializes local state,
           and applies 'cloudflare_r2_bucket.tfstate' to provision the R2 bucket.
  Stage 2: Restores remote backend configuration in infrastructure/cloudflare, and runs
           'tofu init -migrate-state -force-copy' to migrate local state to Cloudflare R2.

Options:
  -h, --help               Display this help message and exit
  -d, --dry-run            Simulate operations without making changes or calling OpenTofu
  -m, --module-dir DIR     Path to Cloudflare module directory (default: infrastructure/cloudflare)
  -b, --bucket NAME        Name of R2 bucket (default: homelab-infra-tfstate)
  -s, --stage STAGE        Stage to execute: 1 (local apply), 2 (remote migration), or all (default: all)
  -e, --env ENV            Target SOPS credentials environment: prod or ci (default: prod)
  -y, --auto-approve       Skip interactive confirmation during OpenTofu apply

Required Environment Variables:
  OpenTofu State Encryption:
    TF_VAR_state_encryption_passphrase  OpenTofu state encryption passphrase (auto-resolved from SOPS if unset)

  Stage 1 (Cloudflare API):
    CLOUDFLARE_API_TOKEN   Cloudflare API Token with Account:R2 Storage:Edit permissions
    CLOUDFLARE_ACCOUNT_ID  Cloudflare Account ID (32 hex characters)
    CLOUDFLARE_ZONE_ID     Cloudflare Zone ID

  Stage 2 (R2 S3-Compatible API):
    AWS_ACCESS_KEY_ID      Cloudflare R2 API Token Access Key ID (auto-resolved from SOPS if unset)
    AWS_SECRET_ACCESS_KEY  Cloudflare R2 API Token Secret Access Key (auto-resolved from SOPS if unset)

Exit Codes:
  0  Success
  1  Invalid argument, missing prerequisite, or command failure
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -m | --module-dir)
      if [[ -z "${2:-}" ]]; then
        log_error "Option --module-dir requires a path argument."
        exit 1
      fi
      MODULE_DIR="$2"
      shift 2
      ;;
    -b | --bucket)
      if [[ -z "${2:-}" ]]; then
        log_error "Option --bucket requires a name argument."
        exit 1
      fi
      BUCKET_NAME="$2"
      shift 2
      ;;
    -s | --stage)
      if [[ -z "${2:-}" ]]; then
        log_error "Option --stage requires an argument (1, 2, or all)."
        exit 1
      fi
      STAGE="$2"
      shift 2
      ;;
    -e | --env)
      if [[ -z "${2:-}" ]]; then
        log_error "Option --env requires an argument (prod or ci)."
        exit 1
      fi
      ENV_TARGET="$2"
      shift 2
      ;;
    -y | --auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate stage argument
if [[ "${STAGE}" != "1" && "${STAGE}" != "2" && "${STAGE}" != "all" ]]; then
  log_error "Invalid stage '${STAGE}'. Must be '1', '2', or 'all'."
  exit 1
fi

# Validate env argument
if [[ "${ENV_TARGET}" != "prod" && "${ENV_TARGET}" != "ci" ]]; then
  log_error "Invalid environment '${ENV_TARGET}'. Must be 'prod' or 'ci'."
  exit 1
fi

# Validate module directory
if [[ ! -d "${MODULE_DIR}" ]]; then
  log_error "Module directory does not exist: ${MODULE_DIR}"
  exit 1
fi

BACKEND_FILE="${MODULE_DIR}/backend.tf"
BACKEND_BACKUP="${MODULE_DIR}/backend.tf.disabled"

# Sync environment variable aliases
if [[ -z "${CLOUDFLARE_API_TOKEN:-}" && -n "${TF_VAR_cloudflare_api_token:-}" ]]; then
  export CLOUDFLARE_API_TOKEN="${TF_VAR_cloudflare_api_token}"
fi
if [[ -z "${TF_VAR_cloudflare_api_token:-}" && -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  export TF_VAR_cloudflare_api_token="${CLOUDFLARE_API_TOKEN}"
fi

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" && -n "${TF_VAR_cloudflare_account_id:-}" ]]; then
  export CLOUDFLARE_ACCOUNT_ID="${TF_VAR_cloudflare_account_id}"
fi
if [[ -z "${TF_VAR_cloudflare_account_id:-}" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  export TF_VAR_cloudflare_account_id="${CLOUDFLARE_ACCOUNT_ID}"
fi

if [[ -z "${CLOUDFLARE_ZONE_ID:-}" && -n "${TF_VAR_cloudflare_zone_id:-}" ]]; then
  export CLOUDFLARE_ZONE_ID="${TF_VAR_cloudflare_zone_id}"
fi
if [[ -z "${TF_VAR_cloudflare_zone_id:-}" && -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  export TF_VAR_cloudflare_zone_id="${CLOUDFLARE_ZONE_ID}"
fi

ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-${TF_VAR_cloudflare_account_id:-}}"

# Ensure mise tools are available on PATH if not already present
if ! command -v tofu &>/dev/null; then
  if [[ -d "${HOME}/.local/share/mise/bin" ]]; then
    export PATH="${HOME}/.local/share/mise/bin:${PATH}"
  fi
  if command -v mise &>/dev/null; then
    eval "$(mise env --shell bash 2>/dev/null || true)"
  fi
fi

# Verify OpenTofu presence
if ! command -v tofu &>/dev/null; then
  log_error "OpenTofu ('tofu') is not installed or not available on PATH."
  exit 1
fi

# Auto-resolve R2 S3 backend credentials and state encryption passphrase from SOPS if unset
resolve_sops_credentials() {
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" && -n "${TF_VAR_state_encryption_passphrase:-}" ]]; then
    return 0
  fi

  local sops_file="${SOPS_SECRETS_FILE:-}"
  if [[ -z "${sops_file}" ]]; then
    if [[ "${ENV_TARGET}" == "prod" ]]; then
      if ! command -v gpg &>/dev/null; then
        log_error "Production environment (--env prod) requires 'gpg' on PATH to decrypt secrets/credentials.sops.yaml (refusing to fall back to CI credentials)."
        exit 1
      fi
      sops_file="${REPO_ROOT}/secrets/credentials.sops.yaml"
    else
      sops_file="${REPO_ROOT}/secrets/credentials.ci.sops.yaml"
    fi
  fi

  if [[ ! -f "${sops_file}" ]]; then
    log_error "SOPS credentials file not found: ${sops_file}"
    return 1
  fi

  if ! command -v sops &>/dev/null || ! command -v yq &>/dev/null; then
    log_error "Both 'sops' and 'yq' are required to resolve credentials from ${sops_file}."
    return 1
  fi

  local creds
  if ! creds=$(sops -d --extract '["opentofu"]' "${sops_file}"); then
    log_error "Failed to decrypt SOPS credentials from ${sops_file}."
    return 1
  fi

  local key_id secret_key state_pass
  key_id=$(printf '%s\n' "${creds}" | yq '.cloudflare_r2_access_key_id // ""')
  secret_key=$(printf '%s\n' "${creds}" | yq '.cloudflare_r2_secret_access_key // ""')
  state_pass=$(printf '%s\n' "${creds}" | yq '.state_encryption_passphrase // ""')

  if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -n "${key_id}" && "${key_id}" != "null" ]]; then
    export AWS_ACCESS_KEY_ID="${key_id}"
    log_info "Auto-resolved AWS_ACCESS_KEY_ID from SOPS (${sops_file##*/})."
  fi
  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" && -n "${secret_key}" && "${secret_key}" != "null" ]]; then
    export AWS_SECRET_ACCESS_KEY="${secret_key}"
    log_info "Auto-resolved AWS_SECRET_ACCESS_KEY from SOPS (${sops_file##*/})."
  fi
  if [[ -z "${TF_VAR_state_encryption_passphrase:-}" && -n "${state_pass}" && "${state_pass}" != "null" ]]; then
    export TF_VAR_state_encryption_passphrase="${state_pass}"
    log_info "Auto-resolved TF_VAR_state_encryption_passphrase from SOPS (${sops_file##*/})."
  fi
}

# Validate credentials
validate_credentials() {
  local missing=0
  local sops_rc=0

  resolve_sops_credentials || sops_rc=$?

  # Both stages run tofu, and the modules have no passphrase default (fail closed).
  if [[ -z "${TF_VAR_state_encryption_passphrase:-}" ]]; then
    log_error "Missing required environment variable: TF_VAR_state_encryption_passphrase (SOPS opentofu.state_encryption_passphrase)"
    missing=$((missing + 1))
  fi

  if [[ "${STAGE}" == "1" || "${STAGE}" == "all" ]]; then
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
      log_error "Missing required environment variable: CLOUDFLARE_API_TOKEN"
      missing=$((missing + 1))
    fi
    if [[ -z "${ACCOUNT_ID}" ]]; then
      log_error "Missing required environment variable: CLOUDFLARE_ACCOUNT_ID (or TF_VAR_cloudflare_account_id)"
      missing=$((missing + 1))
    fi
    if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
      log_error "Missing required environment variable: CLOUDFLARE_ZONE_ID"
      missing=$((missing + 1))
    fi
  fi

  if [[ "${STAGE}" == "2" || "${STAGE}" == "all" ]]; then
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
      log_error "Missing required environment variable: AWS_ACCESS_KEY_ID (R2 Token Access Key ID)"
      missing=$((missing + 1))
    fi
    if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
      log_error "Missing required environment variable: AWS_SECRET_ACCESS_KEY (R2 Token Secret Access Key)"
      missing=$((missing + 1))
    fi
    if [[ -z "${ACCOUNT_ID}" ]]; then
      log_error "Missing required environment variable: CLOUDFLARE_ACCOUNT_ID for R2 endpoint construction"
      missing=$((missing + 1))
    fi
  fi

  if [[ "${sops_rc}" -ne 0 && "${DRY_RUN}" != "true" ]]; then
    log_error "Credential resolution from SOPS failed; aborting."
    exit 1
  fi

  if [[ "${missing}" -gt 0 ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_warn "[dry-run] Missing ${missing} credential(s). Dry-run will continue using placeholder values."
    else
      log_error "Credential validation failed. Please set required environment variables."
      exit 1
    fi
  fi
}

validate_credentials

# Determine R2 endpoint
EFFECTIVE_ACCOUNT_ID="${ACCOUNT_ID:-<account_id>}"
R2_ENDPOINT="https://${EFFECTIVE_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Execute Stage 1
execute_stage_1() {
  log_step "Executing Stage 1: Local state bootstrap for Cloudflare R2 bucket..."

  if [[ -f "${BACKEND_FILE}" ]]; then
    log_info "Temporarily disabling remote backend (${BACKEND_FILE} -> ${BACKEND_BACKUP})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "[dry-run] mv ${BACKEND_FILE} ${BACKEND_BACKUP}"
    else
      mv "${BACKEND_FILE}" "${BACKEND_BACKUP}"
      BACKEND_MOVED=true
    fi
  elif [[ -f "${BACKEND_BACKUP}" ]]; then
    log_info "Remote backend is already disabled (${BACKEND_BACKUP} present)."
  else
    log_info "No backend.tf found in ${MODULE_DIR}; using default local backend."
  fi

  log_info "Initializing OpenTofu with local state backend..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[dry-run] tofu -chdir=${MODULE_DIR} init -input=false"
  else
    tofu -chdir="${MODULE_DIR}" init -input=false
  fi

  local apply_args=(-target=cloudflare_r2_bucket.tfstate -input=false)
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    apply_args+=(-auto-approve)
  fi

  log_info "Applying targeted R2 bucket resource in ${MODULE_DIR}..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[dry-run] tofu -chdir=${MODULE_DIR} apply ${apply_args[*]}"
  else
    tofu -chdir="${MODULE_DIR}" apply "${apply_args[@]}"
  fi

  log_info "Stage 1 complete: R2 state bucket '${BUCKET_NAME}' provisioned."

  if [[ "${STAGE}" == "1" ]]; then
    BACKEND_MOVED=false # Intentionally left disabled for separate Stage 2 execution
    log_info "Stage 1 finished. Remote backend remains in ${BACKEND_BACKUP} until Stage 2 is run."
  fi
}

# Migrate local state to remote backend and verify resource parity before cleanup
migrate_to_remote() {
  tofu -chdir="${MODULE_DIR}" init -migrate-state -force-copy -input=false \
    -backend-config="endpoint=${R2_ENDPOINT}" \
    -backend-config="bucket=${BUCKET_NAME}"

  if [[ -f "${MODULE_DIR}/terraform.tfstate" ]]; then
    log_info "Verifying remote state matches local state before cleanup..."
    local remote_list_raw
    if ! remote_list_raw=$(tofu -chdir="${MODULE_DIR}" state list); then
      log_error "Failed to list remote state via 'tofu state list'; preserving local terraform.tfstate."
      exit 1
    fi

    local remote_sorted local_sorted=""
    remote_sorted=$(printf '%s\n' "${remote_list_raw}" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort)

    if [[ -s "${MODULE_DIR}/terraform.tfstate" ]]; then
      # shellcheck disable=SC2016
      if ! local_sorted=$(yq -r '
        [.resources[]? |
          (((.module // "") | if . != "" then . + "." else "" end) +
           (if .mode == "data" then "data." else "" end) +
           .type + "." + .name) as $base |
          if (.instances | length) > 0 then
            (.instances[] |
              if .index_key == null then $base
              elif (.index_key | tag) == "!!int" then $base + "[" + (.index_key | tostring) + "]"
              else $base + "[\"" + (.index_key | tostring) + "\"]"
              end)
          else
            $base
          end
        ] | .[]
      ' "${MODULE_DIR}/terraform.tfstate" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort); then
        log_error "Failed to parse local ${MODULE_DIR}/terraform.tfstate; preserving local state files."
        exit 1
      fi
    fi

    if [[ "${remote_sorted}" != "${local_sorted}" ]]; then
      log_error "Remote state resource list does not match local terraform.tfstate; preserving local state files."
      exit 1
    fi

    log_info "Cleaning up local state files..."
    rm -f "${MODULE_DIR}/terraform.tfstate" "${MODULE_DIR}/terraform.tfstate.backup"
  fi
}

# Execute Stage 2
execute_stage_2() {
  log_step "Executing Stage 2: Migrating state to Cloudflare R2 remote backend..."

  if [[ -f "${BACKEND_BACKUP}" ]]; then
    log_info "Restoring remote backend configuration (${BACKEND_BACKUP} -> ${BACKEND_FILE})..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "[dry-run] mv ${BACKEND_BACKUP} ${BACKEND_FILE}"
    else
      mv "${BACKEND_BACKUP}" "${BACKEND_FILE}"
      BACKEND_MOVED=false
    fi
  elif [[ ! -f "${BACKEND_FILE}" ]]; then
    log_error "Cannot find backend configuration: neither ${BACKEND_FILE} nor ${BACKEND_BACKUP} exists."
    exit 1
  fi

  log_info "Migrating OpenTofu state to R2 backend (endpoint: ${R2_ENDPOINT})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[dry-run] tofu -chdir=${MODULE_DIR} init -migrate-state -force-copy -input=false -backend-config=endpoint=${R2_ENDPOINT} -backend-config=bucket=${BUCKET_NAME}"
    log_info "[dry-run] tofu -chdir=${MODULE_DIR} state list"
    log_info "[dry-run] rm -f ${MODULE_DIR}/terraform.tfstate ${MODULE_DIR}/terraform.tfstate.backup"
  else
    migrate_to_remote
  fi

  log_info "Stage 2 complete: State successfully migrated to Cloudflare R2 (${BUCKET_NAME})."
}

# Main flow
if [[ "${DRY_RUN}" == "true" ]]; then
  log_warn "DRY-RUN MODE: Simulating operations. No changes will be made to files or infrastructure."
fi

if [[ "${STAGE}" == "1" || "${STAGE}" == "all" ]]; then
  execute_stage_1
fi

if [[ "${STAGE}" == "2" || "${STAGE}" == "all" ]]; then
  execute_stage_2
fi

log_info "Pattern A state backend bootstrap process completed successfully!"
