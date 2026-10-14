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

  # Skip scanning this script and its tests by exact path match
  if [ "$normalized_file" = "scripts/detect-private-keys.sh" ]; then
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
  # Scan for Age private keys
  age_matches=$(git grep --cached -n -I -E -e 'AGE-SECRET-KEY-[0-9A-Z]{59}' -- "${staged_targets[@]}" 2>/dev/null || true)
  if [ -n "$age_matches" ]; then
    reported_files=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      matched_file="${line%%:*}"
      already_reported=false
      if [ ${#reported_files[@]} -gt 0 ]; then
        for rf in "${reported_files[@]}"; do
          if [ "$rf" = "$matched_file" ]; then
            already_reported=true
            break
          fi
        done
      fi
      if [ "$already_reported" = false ]; then
        reported_files+=("$matched_file")
        echo -e "${RED}[ERROR] Security leak detected! Age private key detected in $matched_file!${NC}" >&2
        echo -e "Never commit raw Age private keys to the repository." >&2
        exit_code=1
      fi
    done <<<"$age_matches"
  fi

  # Scan for PEM / SSH / RSA private key headers
  pem_matches=$(git grep --cached -n -I -E -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' -- "${staged_targets[@]}" 2>/dev/null || true)
  if [ -n "$pem_matches" ]; then
    reported_files=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      matched_file="${line%%:*}"
      already_reported=false
      if [ ${#reported_files[@]} -gt 0 ]; then
        for rf in "${reported_files[@]}"; do
          if [ "$rf" = "$matched_file" ]; then
            already_reported=true
            break
          fi
        done
      fi
      if [ "$already_reported" = false ]; then
        reported_files+=("$matched_file")
        echo -e "${RED}[ERROR] Security leak detected! Private key header detected in $matched_file!${NC}" >&2
        echo -e "Never commit raw private keys to the repository." >&2
        exit_code=1
      fi
    done <<<"$pem_matches"
  fi
fi

# 2. Scan disk targets (untracked or non-git)
if [ ${#disk_targets[@]} -gt 0 ]; then
  for file in "${disk_targets[@]}"; do
    [ -f "$file" ] || continue
    if head -c 10 "$file" 2>/dev/null | grep -q "GITCRYPT"; then
      continue
    fi

    # Check for Age private key
    if grep -E -q -e 'AGE-SECRET-KEY-[0-9A-Z]{59}' "$file"; then
      echo -e "${RED}[ERROR] Security leak detected! Age private key detected in $file!${NC}" >&2
      echo -e "Never commit raw Age private keys to the repository." >&2
      exit_code=1
    fi

    # Check for PEM / SSH / RSA private key headers
    if grep -E -q -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' "$file"; then
      echo -e "${RED}[ERROR] Security leak detected! Private key header detected in $file!${NC}" >&2
      echo -e "Never commit raw private keys to the repository." >&2
      exit_code=1
    fi
  done
fi

exit "$exit_code"
