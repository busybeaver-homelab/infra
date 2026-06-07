#!/usr/bin/env bash
# Automatically generate OpenTofu module documentation
# Date: 2026-06-07

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Find all directories containing *.tf files (excluding hidden directories)
find infrastructure -type f -name "*.tf" -not -path "*/.*" -exec dirname {} \; | sort -u | while read -r dir; do
    echo "[INFO] Generating documentation for: $dir"
    # Run terraform-docs with the root configuration file
    terraform-docs --config .terraform-docs.yml "$dir"
done
