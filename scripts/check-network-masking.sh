#!/usr/bin/env bash

set -euo pipefail

# Script to verify that staged files do not contain unencrypted RFC1918 or CGNAT IPv4 addresses:
# - RFC1918: 10.x.x.x/8, 172.16-31.x.x/12, 192.168.x.x/16
# - CGNAT (Tailscale): 100.64-127.x.x/10
#
# Exemptions:
# - *.sops.* (SOPS-encrypted files)
# - docs/* (git-crypt encrypted documentation and plans)
# - backups/* (git-crypt encrypted backups)

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

is_git=false
repo_root=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git=true
  repo_root=$(git rev-parse --show-toplevel)
fi

# Regex matching RFC1918, CGNAT (100.64-127.x.x/10), and IPv6 ULA (fc00::/7) addresses or CIDRs
NETWORK_REGEX='(\b(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|172\.(1[6-9]|2[0-9]|3[01])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?)\b|\b[fF][cdCD][0-9a-fA-F]{2}:[0-9a-fA-F:]+\b)'

# Collect targets: positional arguments or staged files
targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  if [ "$is_git" = true ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && targets+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACM)
    if [ ${#targets[@]} -eq 0 ]; then
      exit 0
    fi
  else
    exit 0
  fi
fi

in_repo_targets=()
disk_targets=()

for file in "${targets[@]}"; do
  # Determine normalized relative path to repository root if inside git
  normalized_file="${file#./}"
  if [ -n "$repo_root" ]; then
    normalized_file="${normalized_file#"$repo_root"/}"
  fi

  # Skip SOPS encrypted files (*.sops.*)
  if [[ "$normalized_file" == *.sops.* ]] || [[ "$normalized_file" == *.sops.yaml ]] || [[ "$normalized_file" == *.sops.yml ]]; then
    continue
  fi

  # Skip agent skills/documentation, git-crypt plans/docs, and git-crypt encrypted backups
  if [[ "$normalized_file" == .agents/* ]] || [[ "$normalized_file" == */.agents/* ]] ||
    [[ "$normalized_file" == .agent/* ]] || [[ "$normalized_file" == */.agent/* ]] ||
    [[ "$normalized_file" == docs/* ]] || [[ "$normalized_file" == */docs/* ]] ||
    [[ "$normalized_file" == backups/* ]] || [[ "$normalized_file" == */backups/* ]]; then
    continue
  fi

  if [ "$is_git" = true ]; then
    # Check if target is inside repository root
    if [[ "$file" = /* ]] && [[ "$file" != "$repo_root"* ]]; then
      disk_targets+=("$file")
    else
      in_repo_targets+=("$file")
    fi
  else
    disk_targets+=("$file")
  fi
done

staged_targets=()
if [ "$is_git" = true ] && [ ${#in_repo_targets[@]} -gt 0 ]; then
  # Determine which targets exist in git index
  while IFS= read -r f; do
    [ -n "$f" ] && staged_targets+=("$f")
  done < <(git ls-files --cached -- "${in_repo_targets[@]}")

  # Any targets in in_repo_targets not in index go to disk_targets (e.g. untracked files on disk)
  if [ ${#staged_targets[@]} -lt ${#in_repo_targets[@]} ]; then
    for target in "${in_repo_targets[@]}"; do
      norm_target="${target#./}"
      if [ -n "$repo_root" ]; then
        norm_target="${norm_target#"$repo_root"/}"
      fi
      in_staged=false
      if [ ${#staged_targets[@]} -gt 0 ]; then
        for s in "${staged_targets[@]}"; do
          if [ "$s" = "$norm_target" ] || [ "$s" = "$target" ]; then
            in_staged=true
            break
          fi
        done
      fi
      if [ "$in_staged" = false ] && [ -f "$target" ]; then
        disk_targets+=("$target")
      fi
    done
  fi
fi

# 1. Batch scan staged targets via git grep --cached
if [ ${#staged_targets[@]} -gt 0 ]; then
  network_matches=$(git grep --cached -n -I -P -e "$NETWORK_REGEX" -- "${staged_targets[@]}" 2>/dev/null || true)
  if [ -n "$network_matches" ]; then
    current_file=""
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      matched_file="${line%%:*}"
      line_info="${line#*:}"
      if [ "$matched_file" != "$current_file" ]; then
        if [ -n "$current_file" ]; then
          echo "" >&2
        fi
        current_file="$matched_file"
        echo -e "${RED}[ERROR] Network masking violation: RFC1918 or CGNAT private IP detected in $matched_file!${NC}" >&2
        echo -e "All internal IPs, subnets, and CIDRs must be treated as sensitive and encrypted via SOPS." >&2
        echo -e "Violating lines:" >&2
      fi
      echo "$line_info" >&2
      exit_code=1
    done <<<"$network_matches"
    if [ -n "$current_file" ]; then
      echo "" >&2
    fi
  fi
fi

# 2. Scan disk targets (untracked or non-git)
if [ ${#disk_targets[@]} -gt 0 ]; then
  for file in "${disk_targets[@]}"; do
    [ -f "$file" ] || continue
    if head -c 10 "$file" 2>/dev/null | grep -q "GITCRYPT"; then
      continue
    fi

    disk_matches=$(grep -n -E -e "$NETWORK_REGEX" "$file" 2>/dev/null || true)
    if [ -n "$disk_matches" ]; then
      echo -e "${RED}[ERROR] Network masking violation: RFC1918 or CGNAT private IP detected in $file!${NC}" >&2
      echo -e "All internal IPs, subnets, and CIDRs must be treated as sensitive and encrypted via SOPS." >&2
      echo -e "Violating lines:" >&2
      echo "$disk_matches" >&2
      echo "" >&2
      exit_code=1
    fi
  done
fi

exit "$exit_code"
