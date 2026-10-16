#!/usr/bin/env bash
# ==============================================================================
# Dynamic Ansible Inventory Generator (STD-AN-20 / REV2-P2-1)
# ==============================================================================
# Translates OpenTofu `ansible_inventory` JSON outputs (from live `tofu output`
# or offline `--from-json` / `--input-json` fixtures) into a gitignored YAML
# inventory at `configuration/inventory/hosts.generated.yml`.
#
# Fails closed (exit 1) if zero hosts are discovered or required host attributes
# are missing.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_FILE="${REPO_ROOT}/configuration/inventories/hosts.generated.yml"
declare -a JSON_INPUTS=()

usage() {
  cat <<'EOF'
Usage: scripts/generate-inventory.sh [OPTIONS]

Options:
  --output <path>              Output YAML inventory path
                               (default: configuration/inventories/hosts.generated.yml)
  --from-json <path>           Read module ansible_inventory JSON from file (repeatable)
  --input-json <[group=]path>  Read module ansible_inventory JSON from file (repeatable)
  -h, --help                   Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: --output requires a file path argument." >&2
        exit 1
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --from-json | --input-json)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "ERROR: $1 requires a file path argument." >&2
        exit 1
      fi
      JSON_INPUTS+=("$2")
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

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

declare -a NORMALIZED_FILES=()

normalize_json_file() {
  local src_file="$1"
  local hint_group="$2"
  local out_file="$3"

  if [[ ! -f "${src_file}" ]]; then
    echo "ERROR: Inventory JSON file not found: ${src_file}" >&2
    exit 1
  fi

  # Normalize supported OpenTofu ansible_inventory shapes into:
  # [{"group": "<group>", "hostname": "<host>", "ansible_host": "<ip>", "private_ip": "<ip>", "role": "<role>"}]
  if ! jq -e --arg hint "${hint_group}" '
    (if type == "object" and has("ansible_inventory") and (.ansible_inventory | type == "object") and (.ansible_inventory | has("value")) then
      .ansible_inventory.value
    elif type == "object" and has("value") and ((.value | type == "object") and ((.value | has("hosts")) or (.value | has("group")))) then
      .value
    else
      .
    end) as $root
    | if ($root | type) != "object" then
        error("root inventory payload must be a JSON object")
      elif ($root | has("hosts")) and (($root.hosts | type) == "object") then
        ($root.group // (if $hint != "" then $hint else "cloud" end)) as $grp
        | [
            $root.hosts | to_entries[] | {
              group: (.value.group // (if (.value.groups? | type) == "array" and (.value.groups | length) > 0 then .value.groups[0] else $grp end)),
              hostname: .key,
              ansible_host: (.value.ansible_host // .value.private_ip // ""),
              private_ip: (.value.private_ip // .value.ansible_host // ""),
              role: (.value.role // .value.tags.role // "compute")
            }
          ]
      else
        [
          $root | to_entries[]
          | select((.value | type) == "object")
          | {
              group: (
                .value.group
                // (if (.value.groups? | type) == "array" and (.value.groups | length) > 0 then .value.groups[0]
                    elif $hint != "" then $hint
                    elif (.key | startswith("oci-")) then "oci"
                    elif (.key | startswith("gcp-")) then "gcp"
                    else "cloud" end)
              ),
              hostname: .key,
              ansible_host: (.value.ansible_host // .value.private_ip // ""),
              private_ip: (.value.private_ip // .value.ansible_host // ""),
              role: (.value.role // .value.tags.role // "compute")
            }
        ]
      end
    | if any(.[]; (.hostname | length) == 0 or (.group | length) == 0 or (.ansible_host | length) == 0) then
        error("every host entry must have non-empty group, hostname, and ansible_host")
      else
        .
      end
  ' "${src_file}" >"${out_file}"; then
    echo "ERROR: Failed to parse or validate inventory JSON from ${src_file}" >&2
    exit 1
  fi
}

idx=0
if [[ ${#JSON_INPUTS[@]} -gt 0 ]]; then
  for spec in "${JSON_INPUTS[@]}"; do
    idx=$((idx + 1))
    hint_group=""
    json_path="${spec}"
    if [[ "${spec}" == *=* ]]; then
      hint_group="${spec%%=*}"
      json_path="${spec#*=}"
    fi
    norm_file="${TMP_DIR}/norm-${idx}.json"
    normalize_json_file "${json_path}" "${hint_group}" "${norm_file}"
    NORMALIZED_FILES+=("${norm_file}")
  done
else
  read -r -a modules <<<"${INVENTORY_MODULES:-oci gcp}"
  for mod in "${modules[@]}"; do
    idx=$((idx + 1))
    raw_file="${TMP_DIR}/raw-${mod}.json"
    norm_file="${TMP_DIR}/norm-${idx}.json"
    mod_dir="${REPO_ROOT}/infrastructure/${mod}"
    if [[ ! -d "${mod_dir}" ]]; then
      echo "ERROR: Infrastructure module directory not found: ${mod_dir}" >&2
      exit 1
    fi
    if ! mise exec -- tofu -chdir="${mod_dir}" output -json ansible_inventory >"${raw_file}"; then
      echo "ERROR: Failed to read 'ansible_inventory' output from infrastructure/${mod}" >&2
      exit 1
    fi
    normalize_json_file "${raw_file}" "${mod}" "${norm_file}"
    NORMALIZED_FILES+=("${norm_file}")
  done
fi

MERGED_JSON="${TMP_DIR}/merged.json"
jq -s '
  flatten
  | if (length == 0) then
      error("Zero hosts discovered across inventory sources (fail-closed)")
    else
      reduce .[] as $item (
        {};
        .all.children.cloud.children[$item.group].hosts[$item.hostname] = {
          ansible_host: $item.ansible_host,
          private_ip: $item.private_ip,
          role: $item.role
        }
      )
    end
' "${NORMALIZED_FILES[@]}" >"${MERGED_JSON}" || {
  echo "ERROR: Inventory generation failed: zero hosts discovered (fail-closed)." >&2
  exit 1
}

mkdir -p "$(dirname "${OUTPUT_FILE}")"
TMP_OUT="${TMP_DIR}/hosts.generated.yml"
{
  echo "# Generated by scripts/generate-inventory.sh - DO NOT EDIT MANUALLY"
  echo "---"
  mise exec -- yq eval -P '.' "${MERGED_JSON}"
} >"${TMP_OUT}"

mv "${TMP_OUT}" "${OUTPUT_FILE}"
