#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/.oxfmtrc.json"

eligible_files=()
for file in "$@"; do
  if [ -f "$file" ]; then
    # Skip if file starts with the binary GITCRYPT signature
    if head -c 10 "$file" 2>/dev/null | grep -q "GITCRYPT"; then
      continue
    fi
    eligible_files+=("$file")
  fi
done

if [ ${#eligible_files[@]} -gt 0 ]; then
  if command -v oxfmt >/dev/null 2>&1; then
    OXFMT_CMD=(oxfmt)
  elif command -v mise >/dev/null 2>&1; then
    OXFMT_CMD=(mise exec -- oxfmt)
  elif [ -x "/opt/homebrew/bin/mise" ]; then
    OXFMT_CMD=(/opt/homebrew/bin/mise exec -- oxfmt)
  elif [ -x "$HOME/.local/bin/mise" ]; then
    OXFMT_CMD=("$HOME/.local/bin/mise" exec -- oxfmt)
  else
    echo "[ERROR] oxfmt not found and mise is unavailable" >&2
    exit 1
  fi

  if [ -f "$CONFIG_FILE" ]; then
    exec "${OXFMT_CMD[@]}" -c "$CONFIG_FILE" --no-error-on-unmatched-pattern "${eligible_files[@]}"
  else
    exec "${OXFMT_CMD[@]}" --no-error-on-unmatched-pattern "${eligible_files[@]}"
  fi
fi
