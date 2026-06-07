#!/usr/bin/env bash

set -euo pipefail

# Script to verify that files ending in *.sops.yaml, *.sops.yml, or *.sops.json
# actually contain SOPS encryption metadata (i.e. prevent committing plaintext secrets).

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

for file in "$@"; do
    # Skip if file does not exist (e.g. deleted file in git stage)
    if [ ! -f "$file" ]; then
        continue
    fi

    # Skip .sops.yaml or .sops.yml configuration files
    base_name=$(basename "$file")
    if [ "$base_name" = ".sops.yaml" ] || [ "$base_name" = ".sops.yml" ]; then
        continue
    fi

    # Check for "sops:" keyword in YAML/YML or '"sops":' in JSON
    if ! grep -q -E '"sops":|sops:' "$file"; then
        echo -e "${RED}[ERROR] Security leak detected!${NC}"
        echo -e "File ${RED}$file${NC} has a SOPS extension but lacks SOPS encryption metadata."
        echo -e "Did you forget to encrypt it using sops?"
        echo -e "To encrypt, run: ${RED}sops -e -i $file${NC}"
        exit_code=1
    fi
done

exit $exit_code
