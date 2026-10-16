#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Remote State Snapshot Utility (STD-OT-16 / REV2-P2-8)
# ==============================================================================
# Copies encrypted OpenTofu remote state from Cloudflare R2
# `homelab-infra/state/<module>/tofu.tfstate` to an immutable timestamped
# snapshot key `homelab-infra/snapshots/<module>/<timestamp>.tfstate`, then
# downloads the snapshot back to a temporary file and verifies SHA-256
# byte-for-byte integrity before succeeding.
#
# Never prints state contents or credentials.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALL_MODULES=(cloudflare dns oci gcp azure homelab github monitoring mesh)
STATE_BUCKET="${STATE_BUCKET:-homelab-infra-tfstate}"
SOPS_SECRETS_FILE="${SOPS_SECRETS_FILE:-${SOPS_FILE:-${REPO_ROOT}/secrets/credentials.sops.yaml}}"

RUN_ALL=0
TARGET_MODULE=""

usage() {
  cat <<'EOF'
Usage: scripts/snapshot-state.sh [<module> | --module <module> | --all]

Options:
  <module>, --module <module>  Snapshot state for a single OpenTofu module:
                               cloudflare, dns, oci, gcp, azure, homelab, github, monitoring, mesh
  --all                        Snapshot state for all 9 OpenTofu modules
  -h, --help                   Show this help message and exit
EOF
}

is_valid_module() {
  local candidate="$1"
  local m
  for m in "${ALL_MODULES[@]}"; do
    if [[ "${m}" == "${candidate}" ]]; then
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --module requires a module name." >&2
        exit 1
      fi
      TARGET_MODULE="$2"
      shift 2
      ;;
    --all)
      RUN_ALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "${TARGET_MODULE}" ]]; then
        TARGET_MODULE="$1"
        shift
      else
        echo "ERROR: Unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ "${RUN_ALL}" -eq 0 && -z "${TARGET_MODULE}" ]]; then
  echo "ERROR: Specify a module name or --all." >&2
  usage >&2
  exit 1
fi

if [[ -n "${TARGET_MODULE}" ]] && ! is_valid_module "${TARGET_MODULE}"; then
  echo "ERROR: Unknown module '${TARGET_MODULE}'. Valid modules: ${ALL_MODULES[*]}" >&2
  exit 1
fi

run_sops() {
  if command -v sops >/dev/null 2>&1; then
    sops "$@"
  else
    mise exec -- sops "$@"
  fi
}

compute_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  else
    shasum -a 256 "${file}" | awk '{print $1}'
  fi
}

if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${R2_ENDPOINT:-}" ]]; then
  if [[ -f "${SOPS_SECRETS_FILE}" ]]; then
    if sops_json="$(run_sops -d --output-type json "${SOPS_SECRETS_FILE}" 2>/dev/null)"; then
      if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        AWS_ACCESS_KEY_ID="$(jq -r '.opentofu.cloudflare_r2_access_key_id // ""' <<<"${sops_json}")"
      fi
      if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        AWS_SECRET_ACCESS_KEY="$(jq -r '.opentofu.cloudflare_r2_secret_access_key // ""' <<<"${sops_json}")"
      fi
      if [[ -z "${R2_ENDPOINT:-}" ]]; then
        R2_ENDPOINT="$(jq -r '
          .opentofu.cloudflare_r2_endpoint
          // (if ((.cloudflare.account_id // .cloudflare.config.account_id // "") != "") then "https://" + (.cloudflare.account_id // .cloudflare.config.account_id) + ".r2.cloudflarestorage.com" else null end)
          // ""
        ' <<<"${sops_json}")"
        if [[ -n "${R2_ENDPOINT}" && "${R2_ENDPOINT}" != http://* && "${R2_ENDPOINT}" != https://* ]]; then
          R2_ENDPOINT="https://${R2_ENDPOINT}"
        fi
      fi
      unset sops_json
    fi
  fi
fi

if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" || -z "${R2_ENDPOINT:-}" ]]; then
  echo "ERROR: R2 credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, R2_ENDPOINT) are required." >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

TMP_DIR="$(umask 077 && mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

TIMESTAMP="${SNAPSHOT_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

snapshot_module() {
  local mod="$1"
  local src_key="homelab-infra/state/${mod}/tofu.tfstate"
  local dst_key="homelab-infra/snapshots/${mod}/${TIMESTAMP}.tfstate"
  local src_uri="s3://${STATE_BUCKET}/${src_key}"
  local dst_uri="s3://${STATE_BUCKET}/${dst_key}"
  local local_src="${TMP_DIR}/${mod}-source.tfstate"
  local local_verify="${TMP_DIR}/${mod}-verify.tfstate"

  if ! aws s3 cp --endpoint-url "${R2_ENDPOINT}" --only-show-errors "${src_uri}" "${local_src}"; then
    echo "ERROR: Failed to download state for module '${mod}' from ${src_uri}" >&2
    return 1
  fi

  if [[ ! -s "${local_src}" ]]; then
    echo "ERROR: Downloaded state file for module '${mod}' is empty (fail-closed)." >&2
    return 1
  fi

  local src_sha
  src_sha="$(compute_sha256 "${local_src}")"

  if ! aws s3 cp --endpoint-url "${R2_ENDPOINT}" --only-show-errors "${local_src}" "${dst_uri}"; then
    echo "ERROR: Failed to upload state snapshot for module '${mod}' to ${dst_uri}" >&2
    return 1
  fi

  if ! aws s3 cp --endpoint-url "${R2_ENDPOINT}" --only-show-errors "${dst_uri}" "${local_verify}"; then
    echo "ERROR: Failed to download snapshot for verification from ${dst_uri}" >&2
    return 1
  fi

  local verify_sha
  verify_sha="$(compute_sha256 "${local_verify}")"

  if [[ "${src_sha}" != "${verify_sha}" ]]; then
    echo "ERROR: SHA-256 mismatch for snapshot '${dst_key}' (expected ${src_sha}, got ${verify_sha})." >&2
    return 1
  fi

  rm -f "${local_src}" "${local_verify}"
  echo "${dst_key}"
}

if [[ "${RUN_ALL}" -eq 1 ]]; then
  modules_to_run=("${ALL_MODULES[@]}")
else
  modules_to_run=("${TARGET_MODULE}")
fi

for mod in "${modules_to_run[@]}"; do
  snapshot_module "${mod}"
done
