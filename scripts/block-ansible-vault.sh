#!/usr/bin/env bash

set -euo pipefail

# Script to scan staged files and block any that contain "$ANSIBLE_VAULT"
# to enforce the SOPS-only secrets rule.

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

  # Skip scanning this script itself by exact path match
  if [ "$normalized_file" = "scripts/block-ansible-vault.sh" ]; then
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
    scannable_staged_targets+=("$s")
  done
fi

# 1. Batch scan staged targets via git grep --cached -a
if [ ${#scannable_staged_targets[@]} -gt 0 ]; then
  # Scan for "$ANSIBLE_VAULT;" header string
  rc=0
  # shellcheck disable=SC2016
  vault_matches=$(git grep --cached -a -n -F -e '$ANSIBLE_VAULT;' -- "${scannable_staged_targets[@]}") || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo -e "${RED}[ERROR] Scanner error: git grep failed (rc=$rc)${NC}" >&2
    exit 2
  fi
  if [ -n "$vault_matches" ]; then
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
        echo -e "${RED}[ERROR] Ansible Vault file detected!${NC}" >&2
        echo -e "File ${RED}$matched_file${NC} contains '\$ANSIBLE_VAULT;'." >&2
        echo -e "Ansible Vault is forbidden in this repository to enforce the SOPS-only secret rule." >&2
        echo -e "Please convert this file to use SOPS encryption." >&2
        exit_code=1
      fi
    done <<<"$vault_matches"
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

    # Check for "$ANSIBLE_VAULT;" header string
    # shellcheck disable=SC2016
    if grep -a -Fq '$ANSIBLE_VAULT;' "$file"; then
      echo -e "${RED}[ERROR] Ansible Vault file detected!${NC}" >&2
      echo -e "File ${RED}$file${NC} contains '\$ANSIBLE_VAULT;'." >&2
      echo -e "Ansible Vault is forbidden in this repository to enforce the SOPS-only secret rule." >&2
      echo -e "Please convert this file to use SOPS encryption." >&2
      exit_code=1
    fi
  done
fi

exit "$exit_code"
