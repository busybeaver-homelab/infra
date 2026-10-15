#!/usr/bin/env bash
# ==============================================================================
# Unified OpenTofu Local Drift Detection Wrapper (STD-OT-42 / STD-CI-36 / REV2-P2-7)
# ==============================================================================
# Runs `tofu plan -detailed-exitcode` against one or all OpenTofu modules using
# the local SOPS credentials file (`secrets/credentials.sops.yaml` by default).
#
# Why a wrapper:
#   - `tofu plan` prints the full diff (including domain names, zone/account/profile
#     IDs, email addresses, and resource attributes). Even locally, dumping those
#     to terminal scrollback or shared logs violates AGENTS.md §1.
#   - This script captures the binary plan to a `0700` temp directory, uses
#     `tofu show -json` + `jq` to emit ONLY action counts and resource addresses
#     (never `.change.before` or `.change.after`), and scrubs any secret values,
#     32-hex IDs, 6-hex NextDNS profile IDs, and email addresses from error lines.
#
# Exit codes:
#   0 — no drift across requested module(s)
#   1 — usage, SOPS, init, or plan error
#   2 — drift detected in at least one module (and no fatal plan errors)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALL_MODULES=(cloudflare dns oci gcp azure homelab github monitoring mesh)
RUN_INIT=1
RUN_ALL=0
TARGET_MODULE=""
MODULE_DIR_OVERRIDE=""
SOPS_FILE="${SOPS_FILE:-${SOPS_SECRETS_FILE:-${REPO_ROOT}/secrets/credentials.sops.yaml}}"

usage() {
  cat <<EOF
Usage: ${DRIFT_INVOKED_AS:-scripts/drift.sh} [--module <name> | --all] [--module-dir <path>] [--init|--no-init]

Options:
  --module <name>      Run drift check for a single module:
                       cloudflare, dns, oci, gcp, azure, homelab, github, monitoring, mesh
  --all                Run drift check across all modules
  --module-dir <path>  Override module directory path (single-module mode)
  --init               Run \`tofu init -input=false\` before planning (default)
  --no-init            Skip \`tofu init\` (when module is already initialized)
  -h, --help           Show this help message and exit
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
    --module-dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --module-dir requires a path." >&2
        exit 1
      fi
      MODULE_DIR_OVERRIDE="$2"
      shift 2
      ;;
    --init)
      RUN_INIT=1
      shift
      ;;
    --no-init)
      RUN_INIT=0
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
  echo "ERROR: Specify --module <name> or --all." >&2
  usage >&2
  exit 1
fi

if [[ -n "${TARGET_MODULE}" ]] && ! is_valid_module "${TARGET_MODULE}"; then
  echo "ERROR: Unknown module '${TARGET_MODULE}'. Valid modules: ${ALL_MODULES[*]}" >&2
  exit 1
fi

run_tool() {
  local bin="$1"
  shift
  if command -v "${bin}" >/dev/null 2>&1; then
    "${bin}" "$@"
  else
    mise exec -- "${bin}" "$@"
  fi
}

ping_healthchecks() {
  local overall_rc="$1"
  if [[ -z "${HEALTHCHECKS_DRIFT_PING_URL:-}" ]]; then
    return 0
  fi
  local ping_url="${HEALTHCHECKS_DRIFT_PING_URL%/}"
  local suffix=""
  if [[ "${overall_rc}" -ne 0 ]]; then
    suffix="/fail"
  fi
  curl -fsS -m 10 --retry 3 "${ping_url}${suffix}" >/dev/null 2>&1 || true
}

run_single_module() {
  local mod="$1"
  local mod_dir="${MODULE_DIR_OVERRIDE:-${REPO_ROOT}/infrastructure/${mod}}"

  if [[ ! -d "${mod_dir}" ]]; then
    echo "Error: module directory not found: ${mod_dir}" >&2
    return 1
  fi

  local tmp_dir
  tmp_dir="$(umask 077 && mktemp -d)"

  local -a secrets_to_mask=()
  local mask_profile_ids=0
  if [[ "${mod}" == "dns" ]]; then
    mask_profile_ids=1
  fi

  if [[ -f "${SOPS_FILE}" ]]; then
    local sops_json
    if sops_json="$(run_tool sops -d --output-type json "${SOPS_FILE}" 2>/dev/null)"; then
      if jq -e 'type == "object"' <<<"${sops_json}" >/dev/null 2>&1; then
        local r2_id r2_secret tf_pass
        r2_id="$(jq -r '.opentofu.cloudflare_r2_access_key_id // empty' <<<"${sops_json}")"
        r2_secret="$(jq -r '.opentofu.cloudflare_r2_secret_access_key // empty' <<<"${sops_json}")"
        tf_pass="$(jq -r '.opentofu.state_encryption_passphrase // empty' <<<"${sops_json}")"
        [[ -n "${r2_id}" ]] && export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${r2_id}}"
        [[ -n "${r2_secret}" ]] && export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${r2_secret}}"
        [[ -n "${tf_pass}" ]] && export TF_ENCRYPTION_PASSPHRASE="${TF_ENCRYPTION_PASSPHRASE:-${tf_pass}}"

        local extracted_secrets=""
        case "${mod}" in
          cloudflare)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .cloudflare.api_token,
                .cloudflare.account_id,
                .cloudflare.zone_id
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          dns)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                (.nextdns.accounts // {} | to_entries[]?.value.api_key)
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          oci)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .oci.tenancy_ocid,
                .oci.user_ocid,
                .oci.fingerprint,
                .oci.region
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          gcp)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .gcp.project_id,
                .gcp.billing_account_id
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          azure)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .azure.subscription_id,
                .azure.tenant_id,
                .azure.client_id,
                .azure.client_secret
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          homelab)
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .unifi_service_account.host,
                .unifi_service_account.username,
                .unifi_service_account.password
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          github)
            local gh_owner gh_token
            gh_owner="$(jq -r '.github.owner // empty' <<<"${sops_json}")"
            gh_token="$(jq -r '.github.token // empty' <<<"${sops_json}")"
            [[ -n "${gh_owner}" ]] && export GITHUB_OWNER="${GITHUB_OWNER:-${gh_owner}}"
            [[ -n "${gh_token}" ]] && export GITHUB_TOKEN="${GITHUB_TOKEN:-${gh_token}}"
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .github.owner,
                .github.token
              ] | .[] | select(type == "string" and length >= 4)
            ' <<<"${sops_json}")"
            ;;
          monitoring)
            local hc_token
            hc_token="$(jq -r '.monitoring.healthchecksio_api_token // empty' <<<"${sops_json}")"
            [[ -n "${hc_token}" ]] && export TF_VAR_healthchecksio_api_token="${TF_VAR_healthchecksio_api_token:-${hc_token}}"
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .monitoring.healthchecksio_api_token
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
          mesh)
            local ts_id ts_secret
            ts_id="$(jq -r '.tailscale.client_id // empty' <<<"${sops_json}")"
            ts_secret="$(jq -r '.tailscale.client_secret // empty' <<<"${sops_json}")"
            [[ -n "${ts_id}" ]] && export TAILSCALE_OAUTH_CLIENT_ID="${TAILSCALE_OAUTH_CLIENT_ID:-${ts_id}}"
            [[ -n "${ts_secret}" ]] && export TAILSCALE_OAUTH_CLIENT_SECRET="${TAILSCALE_OAUTH_CLIENT_SECRET:-${ts_secret}}"
            extracted_secrets="$(jq -r '
              [
                .opentofu.cloudflare_r2_access_key_id,
                .opentofu.cloudflare_r2_secret_access_key,
                .opentofu.state_encryption_passphrase,
                .tailscale.client_id,
                .tailscale.client_secret
              ] | .[] | select(type == "string" and length >= 6)
            ' <<<"${sops_json}")"
            ;;
        esac

        local val
        while IFS= read -r val; do
          [[ -n "${val}" ]] && secrets_to_mask+=("${val}")
        done <<<"${extracted_secrets}"
        unset extracted_secrets
      else
        local raw_val
        while IFS= read -r raw_val; do
          [[ -n "${raw_val}" ]] && secrets_to_mask+=("${raw_val}")
        done <<<"${sops_json}"
      fi
      unset sops_json
    fi
  fi

  mask_stream() {
    local text
    text="$(cat)"
    local s
    for s in "${secrets_to_mask[@]+"${secrets_to_mask[@]}"}"; do
      [[ -n "${s}" ]] && text="${text//"${s}"/<redacted>}"
    done
    if [[ "${mask_profile_ids}" -eq 1 ]]; then
      printf '%s\n' "${text}" | sed -E \
        -e 's/[0-9a-f]{32}/<redacted-id>/g' \
        -e 's/(^|[^0-9a-f])[0-9a-f]{6}([^0-9a-f]|$)/\1<redacted-profile-id>\2/g' \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g'
    else
      printf '%s\n' "${text}" | sed -E \
        -e 's/[0-9a-f]{32}/<redacted-id>/g' \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g'
    fi
  }

  local init_log="${tmp_dir}/init.log"
  local plan_file="${tmp_dir}/tfplan"
  local err_log="${tmp_dir}/plan.err"

  if [[ "${RUN_INIT}" -eq 1 ]]; then
    if ! run_tool tofu -chdir="${mod_dir}" init -input=false -no-color >"${init_log}" 2>&1; then
      echo "Error: tofu init failed for infrastructure/${mod}:" >&2
      grep -E '^(Error:|│)' "${init_log}" | mask_stream >&2 || mask_stream <"${init_log}" >&2
      rm -rf "${tmp_dir}"
      return 1
    fi
  fi

  local rc=0
  run_tool tofu -chdir="${mod_dir}" plan \
    -detailed-exitcode \
    -input=false \
    -lock=false \
    -no-color \
    -out="${plan_file}" >/dev/null 2>"${err_log}" || rc=$?

  case "${rc}" in
    0)
      echo "No drift in infrastructure/${mod}."
      rm -rf "${tmp_dir}"
      return 0
      ;;
    2)
      echo "Drift detected in infrastructure/${mod} (resource addresses and action counts only; values omitted):"
      run_tool tofu -chdir="${mod_dir}" show -json "${plan_file}" | jq -r '
        [ (.resource_changes // [])[]
          | select(.change.actions != ["no-op"] and .change.actions != ["read"])
          | { address: .address, actions: (.change.actions | join(",")) }
        ] as $changes
        | "  Summary: "
          + ([
              "create: \([ $changes[] | select(.actions == "create") ] | length)",
              "update: \([ $changes[] | select(.actions == "update") ] | length)",
              "delete: \([ $changes[] | select(.actions == "delete") ] | length)",
              "replace: \([ $changes[] | select(.actions | contains(",")) ] | length)",
              "forget: \([ $changes[] | select(.actions == "forget") ] | length)"
            ] | join(", ")),
          "  Changed resources:",
          ($changes[] | "    - \(.address) : \(.actions)")
      ' | mask_stream
      rm -rf "${tmp_dir}"
      return 2
      ;;
    *)
      echo "Error: tofu plan failed for infrastructure/${mod} (exit ${rc}). Diagnostic summary (values redacted):" >&2
      grep -E '^(Error:|│)' "${err_log}" | mask_stream >&2 || true
      rm -rf "${tmp_dir}"
      return 1
      ;;
  esac
}

if [[ "${RUN_ALL}" -eq 1 ]]; then
  read -r -a modules_to_run <<<"${DRIFT_MODULES:-${ALL_MODULES[*]}}"
else
  modules_to_run=("${TARGET_MODULE}")
fi

overall_rc=0
for mod in "${modules_to_run[@]}"; do
  mod_rc=0
  run_single_module "${mod}" || mod_rc=$?
  if [[ "${mod_rc}" -eq 1 ]]; then
    overall_rc=1
  elif [[ "${mod_rc}" -eq 2 && "${overall_rc}" -eq 0 ]]; then
    overall_rc=2
  fi
done

ping_healthchecks "${overall_rc}"
exit "${overall_rc}"
