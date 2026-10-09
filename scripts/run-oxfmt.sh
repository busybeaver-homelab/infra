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
  if [ -f "$CONFIG_FILE" ]; then
    exec oxfmt -c "$CONFIG_FILE" --no-error-on-unmatched-pattern "${eligible_files[@]}"
  else
    exec oxfmt --no-error-on-unmatched-pattern "${eligible_files[@]}"
  fi
fi
