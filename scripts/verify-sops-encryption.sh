#!/usr/bin/env bash

set -euo pipefail

# Script to verify that SOPS encrypted files:
# 1. Strictly adhere to the canonical two-file architecture:
#    - secrets/credentials.ci.sops.yaml (Age-encrypted)
#    - secrets/credentials.sops.yaml (PGP-encrypted)
# 2. Inspect git staged index blobs (git show ":$file") when staged to avoid working-copy race conditions.
# 3. Contain valid SOPS encryption metadata: non-empty .sops.mac.
# 4. Contain valid recipients (.sops.age for CI, .sops.pgp for Prod).
# 5. Contain zero unencrypted scalar leaves outside of .sops.

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

ENC_RE='^ENC\[AES256_GCM,data:[A-Za-z0-9+/=]*,iv:[A-Za-z0-9+/=]{16,},tag:[A-Za-z0-9+/=]{16,},type:(str|int|float|bool|bytes|comment)\]$'

# Locate yq command (fail-closed if unavailable)
if command -v yq >/dev/null 2>&1; then
  YQ_CMD=(yq)
elif command -v mise >/dev/null 2>&1 && mise exec -- which yq >/dev/null 2>&1; then
  YQ_CMD=(mise exec -- yq)
else
  echo -e "${RED}[ERROR] Required tool 'yq' is not installed or not in PATH.${NC}" >&2
  exit 2
fi

run_yq() {
  "${YQ_CMD[@]}" "$@"
}

get_content() {
  local target_path="$1"
  local norm_path="$2"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git cat-file -e ":$norm_path" 2>/dev/null; then
    if ! git rev-parse --verify HEAD >/dev/null 2>&1 || ! git diff --no-textconv --cached --quiet -- "$norm_path" 2>/dev/null || git diff --no-textconv --quiet -- "$norm_path" 2>/dev/null; then
      git show ":$norm_path"
      return 0
    fi
  fi
  if [ -f "$target_path" ]; then
    cat "$target_path"
  else
    return 1
  fi
}

# Default to both canonical files when invoked with zero arguments
if [ "$#" -eq 0 ]; then
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel)
    set -- "$repo_root/secrets/credentials.ci.sops.yaml" "$repo_root/secrets/credentials.sops.yaml"
  else
    set -- "secrets/credentials.ci.sops.yaml" "secrets/credentials.sops.yaml"
  fi
fi

for file in "$@"; do
  base_name=$(basename "$file")
  # Skip .sops.yaml / .sops.yml configuration files
  if [ "$base_name" = ".sops.yaml" ] || [ "$base_name" = ".sops.yml" ]; then
    continue
  fi

  # Determine normalized relative path to repository root if inside git
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel)
    normalized_file=$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$file" "$repo_root")
    sops_config="$repo_root/.sops.yaml"
  else
    normalized_file="${file#./}"
    sops_config=".sops.yaml"
  fi

  # Skip documented non-secret files under secrets/
  if [ "$normalized_file" = "secrets/README.md" ] || [ "$normalized_file" = "secrets/gpg-production.pub" ]; then
    continue
  fi

  # 1. Canonical Allowlist Enforcement
  if [ "$normalized_file" != "secrets/credentials.ci.sops.yaml" ] && [ "$normalized_file" != "secrets/credentials.sops.yaml" ]; then
    echo -e "${RED}[ERROR] Security violation: Non-canonical secret file detected: $file${NC}" >&2
    echo -e "All secrets must reside exclusively in 'secrets/credentials.ci.sops.yaml' or 'secrets/credentials.sops.yaml'." >&2
    exit_code=1
    continue
  fi

  # Retrieve staged blob or file content
  if ! content=$(get_content "$file" "$normalized_file"); then
    # File was deleted or does not exist
    continue
  fi

  # Verify valid YAML syntax
  if ! printf '%s\n' "$content" | run_yq eval '.' - >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Security leak detected! File $file is not valid YAML.${NC}" >&2
    exit_code=1
    continue
  fi

  # 2. Verify .sops.mac exists, is non-empty, and matches strict ENC_RE
  sops_mac=$(printf '%s\n' "$content" | run_yq eval -r '(.sops.mac // "")' - | tr -d '[:space:]')
  if [ -z "$sops_mac" ] || [ "$sops_mac" = "null" ]; then
    echo -e "${RED}[ERROR] Security leak detected! Missing or empty .sops.mac in $file.${NC}" >&2
    echo -e "File has a SOPS extension but lacks SOPS encryption metadata." >&2
    exit_code=1
    continue
  fi
  if ! printf '%s\n' "$sops_mac" | grep -Eq "$ENC_RE"; then
    echo -e "${RED}[ERROR] Security leak detected! Invalid .sops.mac format in $file.${NC}" >&2
    exit_code=1
    continue
  fi

  # 3. Verify .sops metadata key allowlist (reject smuggled keys under .sops)
  unknown_sops_keys=$(printf '%s\n' "$content" | run_yq eval -r '
    (.sops | keys // []) | .[]
    | select(
        . != "kms" and . != "gcp_kms" and . != "azure_kv" and . != "hc_vault"
        and . != "age" and . != "pgp" and . != "lastmodified" and . != "mac"
        and . != "version" and . != "unencrypted_suffix" and . != "encrypted_suffix"
        and . != "unencrypted_regex" and . != "encrypted_regex"
        and . != "key_groups" and . != "shamir_threshold"
      )
  ' -)
  if [ -n "$unknown_sops_keys" ]; then
    echo -e "${RED}[ERROR] Security violation: Unauthorized keys under .sops metadata in $file:${NC}" >&2
    while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  - .sops.${line}" >&2
    done <<<"$unknown_sops_keys"
    exit_code=1
    continue
  fi

  # 4. Verify appropriate recipient and match against .sops.yaml when present
  if [ "$normalized_file" = "secrets/credentials.ci.sops.yaml" ]; then
    age_count=$(printf '%s\n' "$content" | run_yq eval '(.sops.age // []) | length' -)
    if [ "$age_count" -lt 1 ]; then
      echo -e "${RED}[ERROR] Security violation: $file must be encrypted with an Age recipient in .sops.age!${NC}" >&2
      exit_code=1
      continue
    fi
  elif [ "$normalized_file" = "secrets/credentials.sops.yaml" ]; then
    pgp_count=$(printf '%s\n' "$content" | run_yq eval '(.sops.pgp // []) | length' -)
    if [ "$pgp_count" -lt 1 ]; then
      echo -e "${RED}[ERROR] Security violation: $file must be encrypted with a PGP recipient in .sops.pgp!${NC}" >&2
      exit_code=1
      continue
    fi
  fi

  if [ -n "${sops_config:-}" ] && [ -f "$sops_config" ]; then
    # shellcheck disable=SC2016
    expected_recipients=$(NORM_PATH="$normalized_file" run_yq eval -r '
      [.creation_rules[] | .path_regex as $re | select(strenv(NORM_PATH) | test($re))][0]
      | [(.key_groups[]?.age[]? // .age), (.key_groups[]?.pgp[]? // .pgp), (.key_groups[]?.kms[]?.arn // .kms), (.key_groups[]?.gcp_kms[]?.resource_id // .gcp_kms), (.key_groups[]?.azure_kv[]?.vault_url // .azure_kv), (.key_groups[]?.hc_vault[]?.vault_address // .hc_vault)]
      | flatten
      | map(select(. != null))
      | .[]
      | split(",")
      | .[]
      | sub("^\s+|\s+$"; "")
      | select(length > 0)
    ' "$sops_config" | sort -u)
    actual_recipients=$(printf '%s\n' "$content" | run_yq eval -r '
      [.sops.age[]?.recipient, .sops.pgp[]?.fp, .sops.kms[]?.arn, .sops.gcp_kms[]?.resource_id, .sops.azure_kv[]?.vault_url, .sops.hc_vault[]?.vault_address, .sops.key_groups[]?.age[]?.recipient, .sops.key_groups[]?.pgp[]?.fp, .sops.key_groups[]?.kms[]?.arn, .sops.key_groups[]?.gcp_kms[]?.resource_id, .sops.key_groups[]?.azure_kv[]?.vault_url, .sops.key_groups[]?.hc_vault[]?.vault_address]
      | flatten
      | map(select(. != null))
      | .[]
      | sub("^\s+|\s+$"; "")
      | select(length > 0)
    ' - | sort -u)
    if [ -z "$expected_recipients" ] || [ "$expected_recipients" != "$actual_recipients" ]; then
      echo -e "${RED}[ERROR] Security violation: Recipient set in $file does not match .sops.yaml creation rule!${NC}" >&2
      diff -u <(printf '%s\n' "$expected_recipients") <(printf '%s\n' "$actual_recipients") >&2 || true
      exit_code=1
      continue
    fi
  fi

  # 5. Reject custom or explicit YAML tags outside of .sops
  tagged_paths=$(printf '%s\n' "$content" | run_yq eval -r '
    del(.sops)
    | [.. | select(style == "tagged" or (tag != "!!map" and tag != "!!seq" and tag != "!!str" and tag != "!!null" and tag != "!!int" and tag != "!!bool" and tag != "!!float")) | (path | join("."))]
    | .[]
  ' -)
  if [ -n "$tagged_paths" ]; then
    echo -e "${RED}[ERROR] Security leak detected! Custom or explicit YAML tag found in $file:${NC}" >&2
    while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  - ${line}" >&2
    done <<<"$tagged_paths"
    exit_code=1
    continue
  fi

  # 6. Check all scalar leaves and map keys outside of .sops for strict encryption grammar
  unencrypted_paths=$(printf '%s\n' "$content" | ENC_REGEX="$ENC_RE" run_yq eval -r '
    del(.sops)
    | [
        (.. | select((tag == "!!str" and (test(strenv(ENC_REGEX)) | not)) or tag == "!!int" or tag == "!!bool" or tag == "!!float") | (path | join("."))),
        (.. | select(kind == "map") | keys | .[] | select(. == "" or test("^ENC\\[")))
      ]
    | .[]
  ' -)
  if [ -n "$unencrypted_paths" ]; then
    echo -e "${RED}[ERROR] Security leak detected! Unencrypted scalar data found in $file:${NC}" >&2
    while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  - ${line}" >&2
    done <<<"$unencrypted_paths"
    exit_code=1
    continue
  fi

  # 7. Reject plaintext YAML comments (any # comment not matching #ENC[AES256_GCM,...])
  comment_leaks=$(printf '%s\n' "$content" | grep -En '(^[[:space:]]*#|[[:space:]]+#)' | grep -Ev "(^[[:space:]]*|[[:space:]]+)#${ENC_RE#^}" || true)
  if [ -n "$comment_leaks" ]; then
    echo -e "${RED}[ERROR] Security leak detected! Plaintext comment found in $file:${NC}" >&2
    while IFS= read -r line; do
      [ -n "$line" ] && echo -e "  - ${line}" >&2
    done <<<"$comment_leaks"
    exit_code=1
    continue
  fi
done

exit $exit_code
