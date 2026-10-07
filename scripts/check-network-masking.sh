#!/usr/bin/env bash

set -euo pipefail

# Script to verify that staged files do not contain unencrypted RFC1918 or CGNAT IPv4 addresses:
# - RFC1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
# - CGNAT (Tailscale): 100.64.0.0/10
#
# Exemptions:
# - *.sops.* (SOPS-encrypted files)
# - tests/fixtures/* (mock test fixtures)
# - docs/plans/* (design and implementation plans)
# - scripts/check-network-masking.sh & tests/scripts/check-network-masking.bats

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

# Regex matching RFC1918 and CGNAT (100.64.0.0/10) addresses or CIDRs
NETWORK_REGEX='\b(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|172\.(1[6-9]|2[0-9]|3[01])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?)\b'

# Collect targets: positional arguments or staged files
targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  if [ "$is_git" = true ]; then
    mapfile -t targets < <(git diff --cached --name-only --diff-filter=ACM)
    if [ ${#targets[@]} -eq 0 ]; then
      exit 0
    fi
  else
    exit 0
  fi
fi

for file in "${targets[@]}"; do
  # Determine normalized relative path to repository root if inside git
  normalized_file="${file#./}"
  if [ -n "$repo_root" ]; then
    normalized_file="${normalized_file#"$repo_root"/}"
  fi

  # Skip scanning this script and its tests
  if [ "$normalized_file" = "scripts/check-network-masking.sh" ] || [ "$normalized_file" = "tests/scripts/check-network-masking.bats" ]; then
    continue
  fi

  # Skip SOPS encrypted files (*.sops.*)
  if [[ "$normalized_file" == *.sops.* ]] || [[ "$normalized_file" == *.sops.yaml ]] || [[ "$normalized_file" == *.sops.yml ]]; then
    continue
  fi

  # Skip agent skills/documentation, test fixtures, and plans
  if [[ "$normalized_file" == .agents/* ]] || [[ "$normalized_file" == */.agents/* ]] ||
    [[ "$normalized_file" == .agent/* ]] || [[ "$normalized_file" == */.agent/* ]] ||
    [[ "$normalized_file" == tests/fixtures/* ]] || [[ "$normalized_file" == */tests/fixtures/* ]] ||
    [[ "$normalized_file" == */fixtures/* ]] ||
    [[ "$normalized_file" == docs/plans/* ]] || [[ "$normalized_file" == */docs/plans/* ]]; then
    continue
  fi

  # Retrieve staged blob or file content
  if ! content=$(get_content "$file" "$normalized_file"); then
    # File was deleted or does not exist
    continue
  fi

  # Check for RFC1918 / CGNAT matches
  if echo "$content" | grep -E -q -e "$NETWORK_REGEX"; then
    echo -e "${RED}[ERROR] Network masking violation: RFC1918 or CGNAT private IP detected in $file!${NC}" >&2
    echo -e "All internal IPs, subnets, and CIDRs must be treated as sensitive and encrypted via SOPS." >&2
    echo -e "Violating lines:" >&2
    echo "$content" | grep -n -E -e "$NETWORK_REGEX" >&2 || true
    echo "" >&2
    exit_code=1
  fi
done

exit "$exit_code"
