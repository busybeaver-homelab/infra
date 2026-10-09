#!/usr/bin/env bash
# Automatically generate OpenTofu module documentation
# Supports optional file/directory arguments for scoped generation

set -euo pipefail

# Resolve script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

if command -v terraform-docs >/dev/null 2>&1; then
  TF_DOCS_CMD=(terraform-docs)
elif command -v mise >/dev/null 2>&1; then
  TF_DOCS_CMD=(mise exec -- terraform-docs)
elif [ -x "/opt/homebrew/bin/mise" ]; then
  TF_DOCS_CMD=(/opt/homebrew/bin/mise exec -- terraform-docs)
elif [ -x "$HOME/.local/bin/mise" ]; then
  TF_DOCS_CMD=("$HOME/.local/bin/mise" exec -- terraform-docs)
else
  echo "[ERROR] terraform-docs not found and mise is unavailable" >&2
  exit 1
fi

dirs=()

if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    if [ -f "$arg" ]; then
      d=$(dirname "$arg")
    elif [ -d "$arg" ]; then
      d="$arg"
    else
      continue
    fi

    # Normalize relative to project root
    rel_d="${d#"$PROJECT_ROOT"/}"
    rel_d="${rel_d#./}"

    if [[ "$rel_d" =~ ^infrastructure(/|$) ]]; then
      dirs+=("$rel_d")
    fi
  done
else
  # Find all directories containing *.tf files (excluding hidden directories)
  while IFS= read -r dir; do
    dirs+=("$dir")
  done < <(find infrastructure -type f -name "*.tf" -not -path "*/.*" -exec dirname {} \; | sort -u)
fi

# De-duplicate directories
if [ "${#dirs[@]}" -gt 0 ]; then
  unique_dirs=()
  while IFS= read -r udir; do
    [ -n "$udir" ] && unique_dirs+=("$udir")
  done < <(printf "%s\n" "${dirs[@]}" | sort -u)

  for dir in "${unique_dirs[@]}"; do
    if [ -d "$dir" ] && compgen -G "$dir/*.tf" >/dev/null 2>&1; then
      echo "[INFO] Generating documentation for: $dir"
      "${TF_DOCS_CMD[@]}" --config .terraform-docs.yml "$dir"
    fi
  done
fi
