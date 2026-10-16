#!/usr/bin/env bash

set -euo pipefail

# Script to verify that staged files do not contain unencrypted private network literals:
# - RFC1918: 10.x.x.x/8, 172.16-31.x.x/12, 192.168.x.x/16
# - CGNAT (Tailscale): 100.64-127.x.x/10
# - IPv6 ULA: fc00::/7
# - Internal/Tailnet hostnames: *.ts.net, *.internal, *.lan, *.home.arpa
#   (allowlisting RFC 2606 / RFC 6761 reserved test domains: *.example.*, *.test.*, *.invalid.*, *.localhost.*)
#
# Exemptions:
# - *.sops.* (SOPS-encrypted files)
# - docs/* (git-crypt encrypted documentation and plans)
# - backups/* (git-crypt encrypted backups)

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

# Regex matching RFC1918, CGNAT (100.64-127.x.x/10), IPv6 ULA (fc00::/7), and internal/tailnet hostnames
IP_CORE_REGEX='(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|172\.(1[6-9]|2[0-9]|3[01])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?|[fF][cdCD][0-9a-fA-F]{2}:[0-9a-fA-F:]+)'
HOSTNAME_CORE_REGEX='(?<![a-zA-Z0-9-])[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.(ts\.net|internal|lan|home\.arpa)(?!\.[a-zA-Z0-9-]|[a-zA-Z0-9-])'
NETWORK_REGEX="(\b${IP_CORE_REGEX}\b|${HOSTNAME_CORE_REGEX})"
ALLOWLIST_HOSTNAME_REGEX='^([a-z0-9-]+\.)*(example|test|invalid|localhost)\.(ts\.net|internal|lan|home\.arpa)$'

# Redact violating tokens on a line; returns 0 and prints redacted token list if violations exist, 1 if all matches are allowlisted.
redact_line_violations() {
  local content="$1"
  local tok tok_lc masked
  local masked_list=()

  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    tok_lc=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')
    if [[ "$tok_lc" =~ $ALLOWLIST_HOSTNAME_REGEX ]]; then
      continue
    fi
    case "$tok_lc" in
      10.*) masked="10.x.x.x" ;;
      172.*) masked="172.x.x.x" ;;
      192.168.*) masked="192.168.x.x" ;;
      100.*) masked="100.x.x.x" ;;
      fc* | fd*) masked="fdxx:..." ;;
      *.ts.net) masked="<redacted>.ts.net" ;;
      *.internal) masked="<redacted>.internal" ;;
      *.lan) masked="<redacted>.lan" ;;
      *.home.arpa) masked="<redacted>.home.arpa" ;;
      *) masked="<redacted>" ;;
    esac
    masked_list+=("$masked")
  done < <(NET_RE="$NETWORK_REGEX" perl -ne 'while (m{$ENV{NET_RE}}g) { print "$&\n"; }' <<<"$content" 2>/dev/null || true)

  if [ ${#masked_list[@]} -eq 0 ]; then
    return 1
  fi
  local IFS=", "
  printf '%s' "${masked_list[*]}"
  return 0
}

# Collect targets: positional arguments or staged files
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

  # Skip SOPS encrypted files (*.sops.*)
  if [[ "$normalized_file" == *.sops.* ]] || [[ "$normalized_file" == *.sops.yaml ]] || [[ "$normalized_file" == *.sops.yml ]]; then
    continue
  fi

  # Skip git-crypt plans/docs and git-crypt encrypted backups
  if [[ "$normalized_file" == docs/* ]] || [[ "$normalized_file" == */docs/* ]] ||
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
  rc=0
  network_matches=$(git grep --cached -a -n -P -e "$NETWORK_REGEX" -- "${scannable_staged_targets[@]}") || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo -e "${RED}[ERROR] Scanner error: git grep failed (rc=$rc)${NC}" >&2
    exit 2
  fi
  if [ -n "$network_matches" ]; then
    current_file=""
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      matched_file="${line%%:*}"
      rest="${line#*:}"
      line_num="${rest%%:*}"
      line_content="${rest#*:}"
      masked_tokens=""
      if ! masked_tokens=$(redact_line_violations "$line_content"); then
        continue
      fi
      if [ "$matched_file" != "$current_file" ]; then
        if [ -n "$current_file" ]; then
          echo "" >&2
        fi
        current_file="$matched_file"
        echo -e "${RED}[ERROR] Network masking violation: private IP or internal hostname detected in $matched_file!${NC}" >&2
        echo -e "All internal IPs, subnets, CIDRs, and internal hostnames must be treated as sensitive and encrypted via SOPS." >&2
        echo -e "Violating lines (redacted):" >&2
      fi
      echo "${line_num}: ${masked_tokens}" >&2
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
    magic_hex=$(head -c 10 "$file" 2>/dev/null | LC_ALL=C od -An -tx1 | tr -d ' \n')
    if [ "$magic_hex" = "00474954435259505400" ]; then
      continue
    fi

    disk_matches=$(NET_RE="$NETWORK_REGEX" perl -ne 'if (m{$ENV{NET_RE}}) { print "$.:$_"; }' "$file" 2>/dev/null || true)
    if [ -n "$disk_matches" ]; then
      file_has_violation=false
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        line_num="${line%%:*}"
        line_content="${line#*:}"
        masked_tokens=""
        if ! masked_tokens=$(redact_line_violations "$line_content"); then
          continue
        fi
        if [ "$file_has_violation" = false ]; then
          file_has_violation=true
          echo -e "${RED}[ERROR] Network masking violation: private IP or internal hostname detected in $file!${NC}" >&2
          echo -e "All internal IPs, subnets, CIDRs, and internal hostnames must be treated as sensitive and encrypted via SOPS." >&2
          echo -e "Violating lines (redacted):" >&2
        fi
        echo "${line_num}: ${masked_tokens}" >&2
        exit_code=1
      done <<<"$disk_matches"
      if [ "$file_has_violation" = true ]; then
        echo "" >&2
      fi
    fi
  done
fi

exit "$exit_code"
