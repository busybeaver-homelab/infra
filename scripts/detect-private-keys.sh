#!/usr/bin/env bash

set -euo pipefail

# Script to scan staged files for unencrypted private keys:
# - age private keys (AGE-SECRET-KEY-...)
# - PEM / OpenSSH / RSA / EC private keys (-----BEGIN ... PRIVATE KEY-----)

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

is_git=false
repo_root=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git=true
  repo_root=$(git rev-parse --show-toplevel)
fi

get_content() {
  local target_path="$1"
  local norm_path="$2"

  if [ "$is_git" = true ] && git cat-file -e ":$norm_path" 2>/dev/null; then
    git show ":$norm_path"
  elif [ -f "$target_path" ]; then
    cat "$target_path"
  else
    return 1
  fi
}

for file in "$@"; do
  # Determine normalized relative path to repository root if inside git
  normalized_file="${file#./}"
  if [ -n "$repo_root" ]; then
    normalized_file="${normalized_file#"$repo_root"/}"
  fi

  # Skip scanning this script and its tests by exact path match
  if [ "$normalized_file" = "scripts/detect-private-keys.sh" ] || [ "$normalized_file" = "tests/scripts/detect-private-keys.bats" ]; then
    continue
  fi

  # Skip git-crypt encrypted files
  if [ -f "$file" ] && head -c 10 "$file" 2>/dev/null | grep -q "GITCRYPT"; then
    continue
  fi

  # Retrieve staged blob or file content
  if ! content=$(get_content "$file" "$normalized_file"); then
    # File was deleted or does not exist
    continue
  fi

  # Skip files if staged content has GITCRYPT header
  if printf '%s' "$content" | head -c 10 2>/dev/null | grep -q "GITCRYPT"; then
    continue
  fi

  # Check for Age private key: AGE-SECRET-KEY-[0-9A-Z]{59}
  if echo "$content" | grep -E -q -e 'AGE-SECRET-KEY-[0-9A-Z]{59}'; then
    echo -e "${RED}[ERROR] Security leak detected! Age private key detected in $file!${NC}" >&2
    echo -e "Never commit raw Age private keys to the repository." >&2
    exit_code=1
  fi

  # Check for PEM / SSH / RSA private key headers
  if echo "$content" | grep -E -q -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY'; then
    echo -e "${RED}[ERROR] Security leak detected! Private key header detected in $file!${NC}" >&2
    echo -e "Never commit raw private keys to the repository." >&2
    exit_code=1
  fi
done

exit $exit_code
