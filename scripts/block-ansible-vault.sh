#!/usr/bin/env bash

set -euo pipefail

# Script to scan staged files and block any that contain "$ANSIBLE_VAULT"
# to enforce the SOPS-only secrets rule.

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

for file in "$@"; do
    # Skip if file does not exist (e.g. deleted file in git stage)
    if [ ! -f "$file" ]; then
        continue
    fi

    # Skip scanning this script itself to avoid false positives
    if [[ "$file" == *"block-ansible-vault.sh" ]]; then
        continue
    fi

    # Ignore binary files
    if grep -qI "" "$file" 2>/dev/null; then
        # Check for "$ANSIBLE_VAULT;" header string
        # shellcheck disable=SC2016
        if grep -Fq '$ANSIBLE_VAULT;' "$file"; then
            echo -e "${RED}[ERROR] Ansible Vault file detected!${NC}"
            echo -e "File ${RED}$file${NC} contains '\$ANSIBLE_VAULT'."
            echo -e "Ansible Vault is forbidden in this repository to enforce the SOPS-only secret rule."
            echo -e "Please convert this file to use SOPS encryption."
            exit_code=1
        fi
    fi
done

exit $exit_code
