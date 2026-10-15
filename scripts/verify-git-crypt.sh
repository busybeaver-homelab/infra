#!/usr/bin/env bash
# Verify that all git-crypt filter-protected files in the Git index are actually
# encrypted with the \0GITCRYPT\0 magic header (R2-GATE-01).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

args=()
for arg in "$@"; do
  case "$arg" in
    --all)
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}[ERROR] verify-git-crypt.sh must be run inside a Git repository.${NC}" >&2
  exit 2
fi

exit_code=0

while IFS= read -r -d '' f && IFS= read -r -d '' _attr && IFS= read -r -d '' filter_val; do
  [ -z "$f" ] && continue
  if [ "$filter_val" != "git-crypt" ]; then
    continue
  fi

  # Skip if deleted from the index
  if ! git cat-file -e ":$f" 2>/dev/null; then
    continue
  fi

  magic_hex=$({ git cat-file -p ":$f" || true; } | head -c 10 | LC_ALL=C od -An -tx1 | tr -d ' \n')
  if [ "$magic_hex" != "00474954435259505400" ]; then
    echo -e "${RED}[ERROR] Plaintext or unencrypted blob detected in git-crypt path: ${f}${NC}" >&2
    echo -e "Ensure git-crypt is unlocked and the filter is configured before staging ${f}." >&2
    exit_code=1
  fi
done < <(
  if [ "${#args[@]}" -gt 0 ]; then
    git ls-files -z -- "${args[@]}" | git check-attr --stdin -z filter
  else
    git ls-files -z | git check-attr --stdin -z filter
  fi
)

if [ "$exit_code" -eq 0 ]; then
  echo -e "${GREEN}All git-crypt protected paths are properly encrypted in the Git index.${NC}"
fi

exit "$exit_code"
