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

# Locate yq command
if command -v yq >/dev/null 2>&1; then
  YQ_CMD="yq"
else
  YQ_CMD="mise exec -- yq"
fi

run_yq() {
  $YQ_CMD "$@"
}

get_content() {
  local target_path="$1"
  local norm_path="$2"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git cat-file -e ":$norm_path" 2>/dev/null; then
    git show ":$norm_path"
  elif [ -f "$target_path" ]; then
    cat "$target_path"
  else
    return 1
  fi
}

for file in "$@"; do
  base_name=$(basename "$file")
  # Skip .sops.yaml / .sops.yml configuration files
  if [ "$base_name" = ".sops.yaml" ] || [ "$base_name" = ".sops.yml" ]; then
    continue
  fi

  # Determine normalized relative path to repository root if inside git
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel)
    normalized_file=$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$file" "$repo_root" 2>/dev/null || echo "$file")
  else
    normalized_file="${file#./}"
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
  if ! echo "$content" | run_yq eval '.' - >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Security leak detected! File $file is not valid YAML.${NC}" >&2
    exit_code=1
    continue
  fi

  # 2. Verify .sops.mac exists and is non-empty
  sops_mac=$(echo "$content" | run_yq eval '(.sops.mac // "")' - 2>/dev/null | tr -d '[:space:]' || echo "")
  if [ -z "$sops_mac" ] || [ "$sops_mac" = "null" ]; then
    echo -e "${RED}[ERROR] Security leak detected! Missing or empty .sops.mac in $file.${NC}" >&2
    echo -e "File has a SOPS extension but lacks SOPS encryption metadata." >&2
    exit_code=1
    continue
  fi

  # 3. Verify appropriate recipient
  if [ "$normalized_file" = "secrets/credentials.ci.sops.yaml" ]; then
    age_count=$(echo "$content" | run_yq eval '(.sops.age // []) | length' - 2>/dev/null || echo 0)
    if [ "$age_count" -lt 1 ]; then
      echo -e "${RED}[ERROR] Security violation: $file must be encrypted with an Age recipient in .sops.age!${NC}" >&2
      exit_code=1
      continue
    fi
  elif [ "$normalized_file" = "secrets/credentials.sops.yaml" ]; then
    pgp_count=$(echo "$content" | run_yq eval '(.sops.pgp // []) | length' - 2>/dev/null || echo 0)
    if [ "$pgp_count" -lt 1 ]; then
      echo -e "${RED}[ERROR] Security violation: $file must be encrypted with a PGP recipient in .sops.pgp!${NC}" >&2
      exit_code=1
      continue
    fi
  fi

  # 4. Check all scalar leaves outside of .sops for encryption pattern
  unencrypted_count=$(echo "$content" | run_yq eval 'del(.sops) | [.. | select(tag == "!!str" or tag == "!!int" or tag == "!!bool" or tag == "!!float") | select(test("^ENC\[AES256_GCM,data:") | not)] | length' - 2>/dev/null || echo 1)
  if [ "$unencrypted_count" -ne 0 ]; then
    echo -e "${RED}[ERROR] Security leak detected! Unencrypted scalar data found in $file ($unencrypted_count unencrypted fields).${NC}" >&2
    exit_code=1
    continue
  fi
done

exit $exit_code
