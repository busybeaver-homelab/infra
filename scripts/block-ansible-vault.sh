#!/usr/bin/env bash

set -euo pipefail

# Script to scan staged files and block any that contain "$ANSIBLE_VAULT"
# to enforce the SOPS-only secrets rule.

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

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
  # Determine normalized relative path to repository root if inside git
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel)
    normalized_file=$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$file" "$repo_root" 2>/dev/null || echo "$file")
  else
    normalized_file="${file#./}"
  fi

  # Skip scanning this script itself by exact path match
  if [ "$normalized_file" = "scripts/block-ansible-vault.sh" ]; then
    continue
  fi

  # Retrieve staged blob or file content
  if ! content=$(get_content "$file" "$normalized_file"); then
    # File was deleted or does not exist
    continue
  fi

  # Check for "$ANSIBLE_VAULT;" header string
  # shellcheck disable=SC2016
  if echo "$content" | grep -Fq '$ANSIBLE_VAULT;'; then
    echo -e "${RED}[ERROR] Ansible Vault file detected!${NC}" >&2
    echo -e "File ${RED}$file${NC} contains '\$ANSIBLE_VAULT;'." >&2
    echo -e "Ansible Vault is forbidden in this repository to enforce the SOPS-only secret rule." >&2
    echo -e "Please convert this file to use SOPS encryption." >&2
    exit_code=1
  fi
done

exit $exit_code
