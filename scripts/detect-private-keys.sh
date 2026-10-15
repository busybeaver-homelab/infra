#!/usr/bin/env bash

set -euo pipefail

# Script to scan staged files for unencrypted private keys:
# - age private keys (AGE-SECRET-KEY-...)
# - PEM / OpenSSH / RSA / EC private keys (-----BEGIN ... PRIVATE KEY-----)
# - binary key containers (*.p12, *.pfx, *.jks, *.kdbx, *.keystore, *.der) and DER magic bytes (0x30 0x82)

RED='\033[0;31m'
NC='\033[0m' # No Color

exit_code=0

if [ -n "${GIT_DIR:-}" ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}[ERROR] Scanner error: invalid GIT_DIR (${GIT_DIR})${NC}" >&2
  exit 2
fi

is_git=false
repo_root=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git=true
  repo_root=$(git rev-parse --show-toplevel)
fi

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  if [ "$is_git" = true ]; then
    diff_rc=0
    diff_out=$(git diff --no-textconv --cached --name-only --diff-filter=ACM) || diff_rc=$?
    if [ "$diff_rc" -ne 0 ]; then
      echo -e "${RED}[ERROR] Scanner error: git diff --cached failed (rc=$diff_rc)${NC}" >&2
      exit 2
    fi
    while IFS= read -r f; do
      [ -n "$f" ] && targets+=("$f")
    done <<<"$diff_out"
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

  # Skip scanning this script by exact path match
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
  ls_rc=0
  ls_out=$(git ls-files --cached -- "${in_repo_targets[@]}") || ls_rc=$?
  if [ "$ls_rc" -ne 0 ]; then
    echo -e "${RED}[ERROR] Scanner error: git ls-files failed (rc=$ls_rc)${NC}" >&2
    exit 2
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && staged_targets+=("$f")
  done <<<"$ls_out"

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

scannable_staged_targets=()
if [ ${#staged_targets[@]} -gt 0 ]; then
  for s in "${staged_targets[@]}"; do
    if ! git cat-file -e ":$s" 2>/dev/null; then
      continue
    fi
    magic_hex=$({ git cat-file -p ":$s" 2>/dev/null || true; } | head -c 10 | LC_ALL=C od -An -tx1 | tr -d ' \n')
    # Skip git-crypt encrypted blobs (\0GITCRYPT\0)
    if [ "$magic_hex" = "00474954435259505400" ]; then
      continue
    fi

    case "$s" in
      *.p12 | *.pfx | *.jks | *.kdbx | *.keystore | *.der)
        echo -e "${RED}[ERROR] Security leak detected! Binary key container ($s) is forbidden!${NC}" >&2
        exit_code=1
        ;;
    esac

    if [ "${magic_hex:0:4}" = "3082" ]; then
      echo -e "${RED}[ERROR] Security leak detected! DER-encoded binary key/container detected in $s!${NC}" >&2
      exit_code=1
    fi

    scannable_staged_targets+=("$s")
  done
fi

# 1. Batch scan staged targets via git grep --cached -a
if [ ${#scannable_staged_targets[@]} -gt 0 ]; then
  # Scan for Age private keys
  rc=0
  age_matches=$(git grep --cached -a -n -E -e 'AGE-SECRET-KEY-[0-9A-Z]{59}' -- "${scannable_staged_targets[@]}") || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo -e "${RED}[ERROR] Scanner error: git grep failed (rc=$rc)${NC}" >&2
    exit 2
  fi
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
  rc=0
  pem_matches=$(git grep --cached -a -n -E -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' -- "${scannable_staged_targets[@]}") || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo -e "${RED}[ERROR] Scanner error: git grep failed (rc=$rc)${NC}" >&2
    exit 2
  fi
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
    magic_hex=$(head -c 10 "$file" 2>/dev/null | LC_ALL=C od -An -tx1 | tr -d ' \n')
    if [ "$magic_hex" = "00474954435259505400" ]; then
      continue
    fi

    case "$file" in
      *.p12 | *.pfx | *.jks | *.kdbx | *.keystore | *.der)
        echo -e "${RED}[ERROR] Security leak detected! Binary key container ($file) is forbidden!${NC}" >&2
        exit_code=1
        ;;
    esac

    if [ "${magic_hex:0:4}" = "3082" ]; then
      echo -e "${RED}[ERROR] Security leak detected! DER-encoded binary key/container detected in $file!${NC}" >&2
      exit_code=1
    fi

    # Check for Age private key
    if grep -a -E -q -e 'AGE-SECRET-KEY-[0-9A-Z]{59}' "$file"; then
      echo -e "${RED}[ERROR] Security leak detected! Age private key detected in $file!${NC}" >&2
      echo -e "Never commit raw Age private keys to the repository." >&2
      exit_code=1
    fi

    # Check for PEM / SSH / RSA private key headers
    if grep -a -E -q -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY' "$file"; then
      echo -e "${RED}[ERROR] Security leak detected! Private key header detected in $file!${NC}" >&2
      echo -e "Never commit raw private keys to the repository." >&2
      exit_code=1
    fi
  done
fi

exit "$exit_code"
