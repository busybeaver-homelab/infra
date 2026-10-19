#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Restic Backup Variable Extractor (STD-AN-09 / STD-OT-25)
# ==============================================================================
# Reads sensitive OpenTofu outputs from infrastructure/{oci,gcp,cloudflare,monitoring}
# in memory (or from JSON fixture files during testing) and emits a single JSON
# object on stdout with keys `tofu_oci_restic`, `tofu_gcp_restic`, and
# `tofu_cloudflare_restic`:
#
#   --mode writer  append-only host writer keys + per-host Healthchecks ping URLs
#                  (consumed by configuration/playbooks/cloud.yml)
#   --mode prune   delete-capable pruner keys + top-level `backup_prune_ping_url`
#                  (consumed by scripts/sync-ops-secrets.sh and the restore drill)
#
# Live mode always resolves the R2 state backend credentials and the state
# encryption passphrase from SOPS inside this process, so restic AWS_* variables
# exported by the caller never leak into the backend. Values travel only through
# pipes (never argv, temp files or here-strings). Fails closed with no stdout if
# any required output is missing or empty.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="writer"
TOFU_DIR="${REPO_ROOT}/infrastructure"
SOPS_FILE="${SOPS_FILE:-${REPO_ROOT}/secrets/credentials.sops.yaml}"
OCI_JSON_FILE=""
GCP_JSON_FILE=""
CLOUDFLARE_JSON_FILE=""
MONITORING_JSON_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/get-tofu-restic-vars.sh [OPTIONS]

Options:
  --mode <writer|prune>     Credential set to emit (default: writer)
  --tofu-dir <dir>          Base infrastructure directory (default: <repo-root>/infrastructure)
  --sops-file <path>        SOPS file holding opentofu.* backend secrets
                            (default: $SOPS_FILE or secrets/credentials.sops.yaml)
  --oci-json <path>         Read infrastructure/oci outputs from JSON file
  --gcp-json <path>         Read infrastructure/gcp outputs from JSON file
  --cloudflare-json <path>  Read infrastructure/cloudflare outputs from JSON file
  --monitoring-json <path>  Read infrastructure/monitoring outputs from JSON file
  -h, --help                Show this help message and exit
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
    --mode)
      require_arg "$@"
      MODE="$2"
      shift 2
      ;;
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
    --oci-json)
      require_arg "$@"
      OCI_JSON_FILE="$2"
      shift 2
      ;;
    --gcp-json)
      require_arg "$@"
      GCP_JSON_FILE="$2"
      shift 2
      ;;
    --cloudflare-json)
      require_arg "$@"
      CLOUDFLARE_JSON_FILE="$2"
      shift 2
      ;;
    --monitoring-json)
      require_arg "$@"
      MONITORING_JSON_FILE="$2"
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

if [[ "${MODE}" != "writer" && "${MODE}" != "prune" ]]; then
  echo "ERROR: --mode must be 'writer' or 'prune' (got '${MODE}')." >&2
  exit 1
fi

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
  # Exported for the tofu child processes only; this script runs in its own process.
  export AWS_ACCESS_KEY_ID="${r2_id}"
  export AWS_SECRET_ACCESS_KEY="${r2_secret}"
  export AWS_DEFAULT_REGION="auto"
  export TF_VAR_state_encryption_passphrase="${passphrase}"
  if [[ -n "${endpoint}" ]]; then
    export AWS_ENDPOINT_URL_S3="${endpoint}"
  fi
}

read_module_json() {
  local mod="$1"
  local file_override="$2"
  local out
  if [[ -n "${file_override}" ]]; then
    if [[ ! -f "${file_override}" ]]; then
      echo "ERROR: Output JSON file not found for module '${mod}': ${file_override}" >&2
      exit 1
    fi
    out="$(cat "${file_override}")"
  else
    if [[ ! -d "${TOFU_DIR}/${mod}" ]]; then
      echo "ERROR: OpenTofu module directory not found: ${TOFU_DIR}/${mod}" >&2
      exit 1
    fi
    if ! out="$(run_tool tofu -chdir="${TOFU_DIR}/${mod}" output -json)"; then
      echo "ERROR: Failed to read OpenTofu outputs from infrastructure/${mod}. Initialise the module against the R2 backend first (docs/runbooks/restic-restore-drill.md, Prerequisites)." >&2
      exit 1
    fi
  fi
  if ! printf '%s' "${out}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: OpenTofu outputs for module '${mod}' are not a JSON object." >&2
    exit 1
  fi
  printf '%s\n' "${out}"
}

# Resolve backend secrets once in this shell; read_module_json runs in subshells.
if [[ -z "${OCI_JSON_FILE}" || -z "${GCP_JSON_FILE}" || -z "${CLOUDFLARE_JSON_FILE}" || -z "${MONITORING_JSON_FILE}" ]]; then
  load_backend_env
fi

oci_raw="$(read_module_json "oci" "${OCI_JSON_FILE}")"
gcp_raw="$(read_module_json "gcp" "${GCP_JSON_FILE}")"
cf_raw="$(read_module_json "cloudflare" "${CLOUDFLARE_JSON_FILE}")"
mon_raw="$(read_module_json "monitoring" "${MONITORING_JSON_FILE}")"

# Slurp the four documents from a pipe so no output value ever appears on argv.
printf '%s\n%s\n%s\n%s\n' "${oci_raw}" "${gcp_raw}" "${cf_raw}" "${mon_raw}" |
  jq -s --arg mode "${MODE}" '
  .[0] as $oci | .[1] as $gcp | .[2] as $cf | .[3] as $mon |
  def req($obj; $mod; $key):
    ($obj[$key].value? // $obj[$key]? // "") as $val
    | if ($val | type) == "string" and ($val | length) > 0 then
        $val
      else
        "ERROR: Missing required OpenTofu output \($key) in module \($mod). Run tofu apply for infrastructure/\($mod).\n" | halt_error(1)
      end;
  def req_hosts($obj; $mod):
    ($obj["ansible_inventory"].value? // $obj["ansible_inventory"]? // null) as $inv
    | if ($inv | type) == "object" and ($inv | length) > 0 then
        ($inv | keys_unsorted | join(" "))
      else
        "ERROR: Missing or empty required OpenTofu output ansible_inventory in module \($mod). Run tofu apply for infrastructure/\($mod).\n" | halt_error(1)
      end;

  if $mode == "writer" then
    {
      tofu_oci_restic: {
        s3_endpoint: req($oci; "oci"; "backup_s3_endpoint"),
        bucket: req($oci; "oci"; "backup_bucket_name"),
        s3_access_key_id: req($oci; "oci"; "backup_s3_access_key_id"),
        s3_secret_access_key: req($oci; "oci"; "backup_s3_secret_access_key"),
        healthcheck_url: req($mon; "monitoring"; "oci_restic_ping_url")
      },
      tofu_gcp_restic: {
        s3_endpoint: req($gcp; "gcp"; "backup_s3_endpoint"),
        bucket: req($gcp; "gcp"; "backup_bucket_name"),
        s3_access_key_id: req($gcp; "gcp"; "backup_hmac_access_id"),
        s3_secret_access_key: req($gcp; "gcp"; "backup_hmac_secret"),
        healthcheck_url: req($mon; "monitoring"; "gcp_restic_ping_url")
      },
      tofu_cloudflare_restic: {
        s3_endpoint: req($cf; "cloudflare"; "r2_backup_endpoint"),
        bucket: req($cf; "cloudflare"; "r2_backup_bucket_name"),
        s3_access_key_id: req($cf; "cloudflare"; "r2_restic_writer_s3_access_key_id"),
        s3_secret_access_key: req($cf; "cloudflare"; "r2_restic_writer_s3_secret_access_key")
      }
    }
  else
    {
      tofu_oci_restic: {
        s3_endpoint: req($oci; "oci"; "backup_s3_endpoint"),
        bucket: req($oci; "oci"; "backup_bucket_name"),
        s3_access_key_id: req($oci; "oci"; "backup_prune_s3_access_key_id"),
        s3_secret_access_key: req($oci; "oci"; "backup_prune_s3_secret_access_key")
      },
      tofu_gcp_restic: {
        s3_endpoint: req($gcp; "gcp"; "backup_s3_endpoint"),
        bucket: req($gcp; "gcp"; "backup_bucket_name"),
        s3_access_key_id: req($gcp; "gcp"; "backup_prune_hmac_access_id"),
        s3_secret_access_key: req($gcp; "gcp"; "backup_prune_hmac_secret")
      },
      tofu_cloudflare_restic: {
        s3_endpoint: req($cf; "cloudflare"; "r2_backup_endpoint"),
        bucket: req($cf; "cloudflare"; "r2_backup_bucket_name"),
        s3_access_key_id: req($cf; "cloudflare"; "r2_restic_prune_s3_access_key_id"),
        s3_secret_access_key: req($cf; "cloudflare"; "r2_restic_prune_s3_secret_access_key")
      },
      oci_hosts: req_hosts($oci; "oci"),
      gcp_hosts: req_hosts($gcp; "gcp"),
      backup_prune_ping_url: req($mon; "monitoring"; "backup_prune_ping_url")
    }
  end
'
