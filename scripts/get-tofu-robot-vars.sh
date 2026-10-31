#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Robot Auth Key Extractor (STD-AN-09 / STD-OT-25)
# ==============================================================================
# Reads the sensitive `robot_auth_key` output from infrastructure/mesh in memory
# (or from a JSON fixture file during testing) and emits a single JSON object on
# stdout:
#
#   {"tofu_robot_auth_key": "<key>"}
#
# consumed by the Valetudo robot playbook to enrol the robot as tag:type-iot.
#
# Live mode always resolves the R2 state backend credentials and the state
# encryption passphrase from SOPS inside this process, so AWS_* variables
# exported by the caller never leak into the backend. Values travel only through
# pipes (never argv, temp files or here-strings). Fails closed with no stdout if
# the output is missing, empty or not a string.
#
# The key is single-use and short-lived. A non-empty key may be expired or
# consumed; this script cannot detect that. Refresh it with
# `tofu apply -replace='tailscale_tailnet_key.robot'` in infrastructure/mesh.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TOFU_DIR="${REPO_ROOT}/infrastructure"
SOPS_FILE="${SOPS_FILE:-${REPO_ROOT}/secrets/credentials.sops.yaml}"
MESH_JSON_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/get-tofu-robot-vars.sh [OPTIONS]

Options:
  --tofu-dir <dir>      Base infrastructure directory (default: <repo-root>/infrastructure)
  --sops-file <path>    SOPS file holding opentofu.* backend secrets
                        (default: $SOPS_FILE or secrets/credentials.sops.yaml)
  --mesh-json <path>    Read infrastructure/mesh outputs from JSON file
  -h, --help            Show this help message and exit
EOF
}

require_arg() {
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    echo "ERROR: $1 requires a value." >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tofu-dir)
      require_arg "$@"
      TOFU_DIR="$2"
      shift 2
      ;;
    --sops-file)
      require_arg "$@"
      SOPS_FILE="$2"
      shift 2
      ;;
    --mesh-json)
      require_arg "$@"
      MESH_JSON_FILE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

run_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@"
  else
    mise exec -- "$@"
  fi
}

sops_value() {
  run_tool sops -d --extract "$1" "${SOPS_FILE}" 2>/dev/null || true
}

load_backend_env() {
  if [[ ! -f "${SOPS_FILE}" ]]; then
    echo "ERROR: SOPS credentials file not found: ${SOPS_FILE}" >&2
    exit 1
  fi
  local r2_id r2_secret passphrase endpoint account_id
  r2_id="$(sops_value '["opentofu"]["cloudflare_r2_access_key_id"]')"
  r2_secret="$(sops_value '["opentofu"]["cloudflare_r2_secret_access_key"]')"
  passphrase="$(sops_value '["opentofu"]["state_encryption_passphrase"]')"
  endpoint="$(sops_value '["opentofu"]["cloudflare_r2_endpoint"]')"
  if [[ -z "${endpoint}" ]]; then
    account_id="$(sops_value '["cloudflare"]["account_id"]')"
    [[ -n "${account_id}" ]] && endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi
  if [[ -z "${r2_id}" || -z "${r2_secret}" || -z "${passphrase}" ]]; then
    echo "ERROR: Could not decrypt opentofu.{cloudflare_r2_access_key_id,cloudflare_r2_secret_access_key,state_encryption_passphrase} from ${SOPS_FILE}." >&2
    exit 1
  fi
  # Exported for the tofu child process only; this script runs in its own process.
  export AWS_ACCESS_KEY_ID="${r2_id}"
  export AWS_SECRET_ACCESS_KEY="${r2_secret}"
  export AWS_DEFAULT_REGION="auto"
  export TF_VAR_state_encryption_passphrase="${passphrase}"
  if [[ -n "${endpoint}" ]]; then
    export AWS_ENDPOINT_URL_S3="${endpoint}"
  fi
}

read_mesh_json() {
  local out
  if [[ -n "${MESH_JSON_FILE}" ]]; then
    if [[ ! -f "${MESH_JSON_FILE}" ]]; then
      echo "ERROR: Output JSON file not found for module 'mesh': ${MESH_JSON_FILE}" >&2
      exit 1
    fi
    out="$(cat "${MESH_JSON_FILE}")"
  else
    if [[ ! -d "${TOFU_DIR}/mesh" ]]; then
      echo "ERROR: OpenTofu module directory not found: ${TOFU_DIR}/mesh" >&2
      exit 1
    fi
    if ! out="$(run_tool tofu -chdir="${TOFU_DIR}/mesh" output -json)"; then
      echo "ERROR: Failed to read OpenTofu outputs from infrastructure/mesh. Initialise the module against the R2 backend first." >&2
      exit 1
    fi
  fi
  if ! printf '%s' "${out}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: OpenTofu outputs for module 'mesh' are not a JSON object." >&2
    exit 1
  fi
  printf '%s\n' "${out}"
}

# Resolve backend secrets in this shell; read_mesh_json runs in a subshell.
if [[ -z "${MESH_JSON_FILE}" ]]; then
  load_backend_env
fi

mesh_raw="$(read_mesh_json)"

# Feed the document through a pipe so the key never appears on argv.
printf '%s\n' "${mesh_raw}" | jq -c '
  (.robot_auth_key.value? // .robot_auth_key? // "") as $val
  | if ($val | type) == "string" and ($val | length) > 0 then
      { tofu_robot_auth_key: $val }
    else
      "ERROR: Missing required OpenTofu output robot_auth_key in module mesh. Run tofu apply for infrastructure/mesh.\n" | halt_error(1)
    end
'
