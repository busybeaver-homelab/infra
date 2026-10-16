#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Restic Backup Variable Extractor for Ansible (STD-AN-09 / STD-OT-25)
# ==============================================================================
# Reads sensitive OpenTofu outputs from infrastructure/{oci,gcp,cloudflare,monitoring}
# in memory (or from JSON fixture files during testing) and emits a single JSON
# object on stdout with keys `tofu_oci_restic`, `tofu_gcp_restic`, and
# `tofu_cloudflare_restic` for consumption by `configuration/playbooks/cloud.yml`.
#
# Never writes sensitive credentials to disk and fails closed if any required
# OpenTofu output is missing or empty.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OCI_JSON_FILE=""
GCP_JSON_FILE=""
CLOUDFLARE_JSON_FILE=""
MONITORING_JSON_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/get-tofu-restic-vars.sh [OPTIONS]

Options:
  --oci-json <path>         Read infrastructure/oci outputs from JSON file
  --gcp-json <path>         Read infrastructure/gcp outputs from JSON file
  --cloudflare-json <path>  Read infrastructure/cloudflare outputs from JSON file
  --monitoring-json <path>  Read infrastructure/monitoring outputs from JSON file
  -h, --help                Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --oci-json)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        echo "ERROR: --oci-json requires a file path." >&2
        exit 1
      }
      OCI_JSON_FILE="$2"
      shift 2
      ;;
    --gcp-json)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        echo "ERROR: --gcp-json requires a file path." >&2
        exit 1
      }
      GCP_JSON_FILE="$2"
      shift 2
      ;;
    --cloudflare-json)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        echo "ERROR: --cloudflare-json requires a file path." >&2
        exit 1
      }
      CLOUDFLARE_JSON_FILE="$2"
      shift 2
      ;;
    --monitoring-json)
      [[ $# -ge 2 && -n "${2:-}" ]] || {
        echo "ERROR: --monitoring-json requires a file path." >&2
        exit 1
      }
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

run_tofu() {
  if command -v tofu >/dev/null 2>&1; then
    tofu "$@"
  else
    mise exec -- tofu "$@"
  fi
}

read_module_json() {
  local mod="$1"
  local file_override="$2"
  if [[ -n "${file_override}" ]]; then
    if [[ ! -f "${file_override}" ]]; then
      echo "ERROR: Output JSON file not found for module '${mod}': ${file_override}" >&2
      exit 1
    fi
    cat "${file_override}"
  else
    run_tofu -chdir="${REPO_ROOT}/infrastructure/${mod}" output -json
  fi
}

oci_raw="$(read_module_json "oci" "${OCI_JSON_FILE}")"
gcp_raw="$(read_module_json "gcp" "${GCP_JSON_FILE}")"
cf_raw="$(read_module_json "cloudflare" "${CLOUDFLARE_JSON_FILE}")"
mon_raw="$(read_module_json "monitoring" "${MONITORING_JSON_FILE}")"

jq -n \
  --argjson oci "${oci_raw}" \
  --argjson gcp "${gcp_raw}" \
  --argjson cf "${cf_raw}" \
  --argjson mon "${mon_raw}" '
  def req($obj; $mod; $keys):
    ([ $keys[] as $k | ($obj[$k].value? // $obj[$k]? // "") | select(type == "string" and length > 0) ][0] // "") as $val
    | if ($val | length) == 0 then
        "ERROR: Missing required OpenTofu output (" + ($keys | join(" or ")) + ") in module " + $mod + ".\n" | halt_error(1)
      else
        $val
      end;

  {
    tofu_oci_restic: {
      s3_endpoint: req($oci; "oci"; ["backup_s3_endpoint"]),
      bucket: req($oci; "oci"; ["backup_bucket_name"]),
      s3_access_key_id: req($oci; "oci"; ["backup_s3_access_key_id"]),
      s3_secret_access_key: req($oci; "oci"; ["backup_s3_secret_access_key"]),
      healthcheck_url: req($mon; "monitoring"; ["oci_restic_ping_url", "restic_backup_ping_url"])
    },
    tofu_gcp_restic: {
      s3_endpoint: req($gcp; "gcp"; ["backup_s3_endpoint"]),
      bucket: req($gcp; "gcp"; ["backup_bucket_name"]),
      s3_access_key_id: req($gcp; "gcp"; ["backup_hmac_access_id"]),
      s3_secret_access_key: req($gcp; "gcp"; ["backup_hmac_secret"]),
      healthcheck_url: req($mon; "monitoring"; ["gcp_restic_ping_url"])
    },
    tofu_cloudflare_restic: {
      s3_endpoint: req($cf; "cloudflare"; ["r2_backup_endpoint", "r2_s3_endpoint"]),
      bucket: req($cf; "cloudflare"; ["r2_backup_bucket_name", "r2_backups_dr_bucket_name"]),
      s3_access_key_id: req($cf; "cloudflare"; ["r2_restic_writer_s3_access_key_id"]),
      s3_secret_access_key: req($cf; "cloudflare"; ["r2_restic_writer_s3_secret_access_key"])
    }
  }
'
