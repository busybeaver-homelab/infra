#!/usr/bin/env bash
# scripts/check-sops-secret-leaks.sh
#
# Prevents SOPS-encrypted secrets from leaking into plaintext repository files
# and enforces secret value disjointness between production and CI SOPS files:
#   - secrets/credentials.sops.yaml (production, GPG-encrypted)
#   - secrets/credentials.ci.sops.yaml (CI decoy, Age-encrypted)
#
# Usage: check-sops-secret-leaks.sh [--check-files] [--all-files] [--check-disjointness] [--] [file ...]
#   --check-files         scan the given files (default: staged files)
#   --all-files           scan every file in the index
#   --check-disjointness  fail if the CI file shares any sensitive value with production
#   (no mode flag)        --check-files + --check-disjointness
#
# What is scanned:
#   - Files in the index are scanned as their staged blobs (git grep --cached), so
#     the check judges exactly what will be committed. git-crypt paths are stored
#     as ciphertext and need no exemption. Binary blobs are scanned too.
#   - Files outside the index (or outside a git repository) are scanned on disk.
#   - Only the canonical SOPS files and .sops.yaml are never scanned.
#
# Which SOPS values are searched for (case-insensitive):
#   - String and numeric leaves outside the schema allowlist (is_allowlisted_path).
#   - >= 8 characters: substring match; 6-7 characters: whole-word match;
#     shorter values are not searched (too ambiguous to match reliably).
#   - Each line (>= 16 characters) of a multi-line value, e.g. PEM/OpenSSH keys.
#   - The bech32 body of an AGE-SECRET-KEY-1... value (split-string evasion).
#   - Public RFC decoys (RFC 2606/5737, <placeholders>, decoy-*) are skipped for
#     CI values only; production values are always searched.
#
# Disjointness: a non-allowlisted CI value fails when it equals any production
# value (at any key path) or when one contains the other (>= 16 characters).
#
# Fail-closed policy:
#   - Locally, both SOPS files must decrypt to at least one value.
#   - On GitHub Actions (GITHUB_ACTIONS=true) the production GPG key is never
#     present: production is skipped with a notice (disjointness is enforced by
#     the local pre-commit hook only), but the CI file must decrypt, so a missing
#     SOPS_AGE_KEY fails the run.
#   - Any scanner error fails the run.
#
# Security & Log Hygiene (AGENTS.md §1, STD-CI-33):
#   - NEVER prints decrypted secret values or raw matching line contents.
#   - Reports only <file>:<line> and <sops_file>:<yaml_key_path>.
#   - Decrypted values stay in memory (shell variables, pipes, process
#     substitution); no plaintext is written to disk.

set -euo pipefail

if { ! command -v sops >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1; } && [ -d "${HOME:-}/.local/share/mise/shims" ]; then
  export PATH="${HOME}/.local/share/mise/shims:${PATH}"
fi

RED='\033[0;31m'
NC='\033[0m'

PROD_SOPS_FILE="${PROD_SOPS_FILE:-secrets/credentials.sops.yaml}"
CI_SOPS_FILE="${CI_SOPS_FILE:-secrets/credentials.ci.sops.yaml}"
PROD_LABEL="secrets/credentials.sops.yaml"
CI_LABEL="secrets/credentials.ci.sops.yaml"

do_check_files=false
do_check_disjointness=false
do_all_files=false
file_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --check-files)
      do_check_files=true
      shift
      ;;
    --all-files)
      do_check_files=true
      do_all_files=true
      shift
      ;;
    --check-disjointness)
      do_check_disjointness=true
      shift
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        file_args+=("$1")
        shift
      done
      ;;
    -*)
      echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
      exit 1
      ;;
    *)
      file_args+=("$1")
      shift
      ;;
  esac
done

if [ "$do_check_files" = false ] && [ "$do_check_disjointness" = false ]; then
  do_check_files=true
  do_check_disjointness=true
fi

on_github_actions=false
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  on_github_actions=true
fi

is_git=false
repo_root=""
repo_prefix=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git=true
  repo_root=$(git rev-parse --show-toplevel)
  repo_prefix=$(git rev-parse --show-prefix)
fi

is_canonical_sops_file() {
  case "$1" in
    "$PROD_LABEL" | "$CI_LABEL" | .sops.yaml) return 0 ;;
  esac
  return 1
}

# Index targets are repo-root-relative paths scanned as staged blobs;
# disk targets are paths outside the index, scanned as given.
index_targets=()
disk_targets=()
if [ "$do_check_files" = true ] && [ "$do_all_files" = false ]; then
  if [ ${#file_args[@]} -eq 0 ] && [ "$is_git" = true ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && file_args+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACM)
  fi

  indexed=""
  if [ "$is_git" = true ] && [ ${#file_args[@]} -gt 0 ]; then
    indexed=$(git --literal-pathspecs ls-files --cached --full-name -- "${file_args[@]}" 2>/dev/null || true)
  fi

  if [ ${#file_args[@]} -gt 0 ]; then
    for file in "${file_args[@]}"; do
      rel="${file#./}"
      if [ -n "$repo_root" ]; then
        case "$rel" in
          "$repo_root"/*) rel="${rel#"$repo_root"/}" ;;
          /*) ;;
          *) rel="${repo_prefix}${rel}" ;;
        esac
      fi

      if is_canonical_sops_file "$rel"; then
        continue
      fi

      if [ -n "$indexed" ] && printf '%s\n' "$indexed" | grep -Fxq -- "$rel"; then
        index_targets+=("$rel")
      elif [ -f "$file" ]; then
        disk_targets+=("$file")
      fi
    done
  fi
fi

# Fast exit if only checking files and no eligible files are staged/passed
if [ "$do_check_disjointness" = false ] && [ "$do_all_files" = false ] &&
  [ ${#index_targets[@]} -eq 0 ] && [ ${#disk_targets[@]} -eq 0 ]; then
  exit 0
fi

# Emits one "<label>\t<key_path>\t<is_multiline>\t<line>" record per value line.
# Dots inside key names are escaped as %2E so they cannot forge allowlisted paths.
extract_sops_leaves() {
  local sops_file="$1"
  local label="$2"
  local decrypted

  if [ ! -f "$sops_file" ]; then
    echo -e "${RED}[ERROR] Failed to decrypt ${label}: file not found.${NC}" >&2
    return 1
  fi

  if ! decrypted=$(sops --decrypt "$sops_file" 2>/dev/null); then
    echo -e "${RED}[ERROR] Failed to decrypt ${label}. Ensure your GPG/Age keys are available (fail-closed policy).${NC}" >&2
    return 1
  fi

  # yq stderr is suppressed because parse errors could echo decrypted content
  # shellcheck disable=SC2016 # $p/$v/$m/$l are yq variables
  if ! printf '%s\n' "$decrypted" | yq -r '
    .. | select(tag == "!!str" or tag == "!!int" or tag == "!!float")
    | (path | map(tostring | sub("\.", "%2E")) | join(".")) as $p
    | tostring as $v
    | ($v | test("\n") | tostring) as $m
    | ($v | split("\n") | .[]) as $l
    | [$p, $m, $l] | join("\t")
  ' 2>/dev/null | awk -v src="$label" '$0 != "" { print src "\t" $0 }'; then
    echo -e "${RED}[ERROR] Failed to parse decrypted ${label} (fail-closed policy).${NC}" >&2
    return 1
  fi
}

decrypt_or_fail() {
  local sops_file="$1"
  local label="$2"
  local leaves
  if ! leaves=$(extract_sops_leaves "$sops_file" "$label"); then
    if [ "$on_github_actions" = true ] && [ "$label" = "$CI_LABEL" ]; then
      echo -e "${RED}[ERROR] ${label} must decrypt on GitHub Actions: provide SOPS_AGE_KEY (secrets.SOPS_AGE_KEY_CI) to this step.${NC}" >&2
    fi
    return 1
  fi
  if [ -z "$leaves" ]; then
    echo -e "${RED}[ERROR] ${label} decrypted to no values; refusing to pass an empty scan (fail-closed policy).${NC}" >&2
    return 1
  fi
  printf '%s\n' "$leaves"
}

prod_decrypted=false
prod_leaves=""
if [ "$on_github_actions" = true ]; then
  if prod_leaves=$(extract_sops_leaves "$PROD_SOPS_FILE" "$PROD_LABEL" 2>/dev/null) && [ -n "$prod_leaves" ]; then
    prod_decrypted=true
  else
    prod_leaves=""
    echo "::notice::${PROD_LABEL} is not decryptable on GitHub Actions; scanning CI values only. Prod/CI disjointness is enforced by the local pre-commit hook."
  fi
else
  prod_leaves=$(decrypt_or_fail "$PROD_SOPS_FILE" "$PROD_LABEL")
  prod_decrypted=true
fi
ci_leaves=$(decrypt_or_fail "$CI_SOPS_FILE" "$CI_LABEL")

# Classifies every value line and emits typed records (never to disk):
#   L\t<needle>               substring needle
#   W\t<needle>               whole-word needle (6-7 characters)
#   M\t<needle>\t<src:path>   needle -> origin map for reporting
#   C\t<ci_key_path>          disjointness violation
analysis=$(
  printf '%s\n%s\n' "$prod_leaves" "$ci_leaves" | awk -F'\t' \
    -v prod_label="$PROD_LABEL" \
    -v ci_label="$CI_LABEL" \
    -v check_disjoint="$do_check_disjointness" \
    -v prod_ok="$prod_decrypted" '
# Structural/public values, anchored to the real schema paths.
function is_allowlisted_path(p) {
  if (p ~ /^(is_production|gcp\.(region|zone|breakglass_user)|oci\.(region|breakglass_user)|github\.owner)$/) return 1
  if (p ~ /^compose\.hosts\.[0-9]+\.target$/) return 1
  if (p ~ /^github\.config\.repositories\.[^.]+\.(name|description|topics\.[0-9]+)$/) return 1
  if (p ~ /^github\.config\.deploy_keys\.[^.]+\.title$/) return 1
  if (p ~ /^nextdns\.(accounts\.[^.]+\.account_name|config\.accounts\.account_5\.profile_name)$/) return 1
  if (p ~ /^cloudflare\.config\.iam\.tokens\.[^.]+\.policies\.[0-9]+\.(effect|permission_groups\.[0-9]+)$/) return 1
  if (p ~ /^cloudflare\.config\.zero_trust\.split_tunnel_excludes\.[0-9]+\.(address|description)$/) return 1
  if (p ~ /^cloudflare\.config\.zones\.[^.]+\.dns_records\.[^.]+\.(type|ttl|proxied|priority)$/) return 1
  if (p ~ /^cloudflare\.config\.zones\.[^.]+\.email_catch_all\.(enabled|actions\.[0-9]+\.type)$/) return 1
  if (p ~ /^cloudflare\.config\.zones\.[^.]+\.email_rules\.[^.]+\.(enabled|priority|matchers\.[0-9]+\.(field|type)|actions\.[0-9]+\.type)$/) return 1
  if (p ~ /^cloudflare\.config\.zones\.[^.]+\.waf_custom\.rules\.[0-9]+\.(action|enabled)$/) return 1
  return 0
}

# Public constants that are never secret, in either file.
function is_public_constant(val,    low) {
  low = tolower(val)
  if (val ~ /^-----(BEGIN|END) /) return 1
  if (low ~ /^(placeholder|changeme|disabled|enabled|true|false|null|none)$/) return 1
  if (low ~ /^(gcp-default-vm|oci-amd-[12]|oci-arm-1)$/) return 1
  if (low == "https://storage.googleapis.com") return 1
  # RFC 5737 / RFC 3849 documentation addresses (e.g. Cloudflare dummy origins)
  if (val ~ /^(192\.0\.2|198\.51\.100|203\.0\.113)\.[0-9]+(\/[0-9]+)?$/) return 1
  if (low ~ /^2001:db8:[0-9a-f:]*(\/[0-9]+)?$/) return 1
  # URL templates with <identifier> placeholders; real values get searched once filled in
  if (low ~ /^[a-z][a-z0-9+.-]*:\/\/.*<[a-z_][a-z0-9_]*>/) return 1
  return 0
}

# Public RFC decoys and synthetic markers; applied to CI values only.
function is_ci_decoy(val,    low) {
  low = tolower(val)
  if (val ~ /<[^>]+>/) return 1
  if (low ~ /(^|\.|@|-)example(\.|-|$)/) return 1
  if (low ~ /^0{16,}[0-9a-f]{0,4}$/) return 1
  if (low ~ /(^|=)decoy[-_.]/) return 1
  # Throwaway values intentionally reused in CI workflows (STD-CI-25)
  if (low == "ci-validation-dummy-passphrase-32ch" || low == "012345-6789ab-cdef01") return 1
  return 0
}

function emit_needle(n, kind, origin,    low) {
  low = tolower(n)
  if (!((kind SUBSEP low) in seen_needle)) {
    seen_needle[kind SUBSEP low] = 1
    print kind "\t" low
  }
  if (!((low SUBSEP origin) in seen_map)) {
    seen_map[low SUBSEP origin] = 1
    print "M\t" low "\t" origin
  }
}

{
  src = $1
  path = $2
  multi = $3
  line = $4
  for (i = 5; i <= NF; i++) line = line "\t" $i
  gsub(/\r/, "", line)
  gsub(/^[ \t]+|[ \t]+$/, "", line)

  if (line == "" || is_allowlisted_path(path) || is_public_constant(line)) next
  if (src == ci_label && is_ci_decoy(line)) next

  len = length(line)
  if (multi == "true" && len < 16) next
  if (len < 6) next

  origin = src ":" path
  emit_needle(line, (len >= 8 ? "L" : "W"), origin)

  # Split-string evasion: AGE-SECRET-KEY-1 + bech32 body
  if (toupper(line) ~ /^AGE-SECRET-KEY-1[A-Z0-9]+$/ && len > 24) {
    emit_needle(substr(line, 17), "L", origin)
  }

  low = tolower(line)
  if (src == prod_label) {
    prod_val[low] = 1
  } else if (src == ci_label) {
    n_ci++
    ci_val[n_ci] = low
    ci_path[n_ci] = path
  }
}

END {
  if (check_disjoint != "true" || prod_ok != "true") exit
  for (i = 1; i <= n_ci; i++) {
    v = ci_val[i]
    hit = (v in prod_val)
    if (!hit) {
      for (p in prod_val) {
        if ((length(p) >= 16 && index(v, p) > 0) || (length(v) >= 16 && index(p, v) > 0)) {
          hit = 1
          break
        }
      }
    }
    if (hit) print "C\t" ci_path[i]
  }
}
'
)

records() {
  printf '%s\n' "$analysis" | awk -F'\t' -v kind="$1" '$1 == kind { sub(/^[^\t]*\t/, ""); print }'
}

exit_code=0

# 1. Prod-vs-CI SOPS disjointness
if [ "$do_check_disjointness" = true ]; then
  collisions=$(records C | sort -u)
  if [ -n "$collisions" ]; then
    echo -e "${RED}[ERROR] SOPS Disjointness violation: ${CI_LABEL} contains production secret value(s)!${NC}" >&2
    echo "The following CI key path(s) equal or embed a production value:" >&2
    while IFS= read -r col_path; do
      [ -n "$col_path" ] && echo "  - ${CI_LABEL}:${col_path}" >&2
    done < <(printf '%s\n' "$collisions")
    echo "Replace the value(s) in ${CI_LABEL} with synthetic decoy values." >&2
    exit_code=1
  fi
fi

# Runs one fixed-string, case-insensitive scan; prints "<file>:<line>:<content>" hits.
# Exit status 1 (no match) is success; anything above 1 is a scanner failure.
scan_with() {
  local word_flag="$1"
  shift
  local rc=0
  "$@" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo -e "${RED}[ERROR] SOPS leak scanner failed (exit ${rc}${word_flag:+, whole-word pass}); refusing to pass an incomplete scan.${NC}" >&2
    return 1
  fi
}

run_scans() {
  local kind="$1"
  local word_flag=""
  [ "$kind" = W ] && word_flag="-w"
  [ -z "$(records "$kind")" ] && return 0

  # Each pass returns explicitly: errexit does not apply inside command substitution on bash 3.2
  if [ "$do_all_files" = true ] && [ "$is_git" = true ]; then
    # shellcheck disable=SC2086 # word_flag is empty or a single flag
    scan_with "$word_flag" git -C "$repo_root" grep --cached -n --text -F -i $word_flag -f <(records "$kind") -- \
      ':(top)' ":(top,exclude)${PROD_LABEL}" ":(top,exclude)${CI_LABEL}" ':(top,exclude).sops.yaml' || return 1
  fi
  if [ ${#index_targets[@]} -gt 0 ]; then
    # shellcheck disable=SC2086
    scan_with "$word_flag" git -C "$repo_root" --literal-pathspecs grep --cached -n --text -F -i $word_flag -f <(records "$kind") -- "${index_targets[@]}" || return 1
  fi
  if [ ${#disk_targets[@]} -gt 0 ]; then
    # shellcheck disable=SC2086
    LC_ALL=C scan_with "$word_flag" grep -n -H -a -F -i $word_flag -f <(records "$kind") -- "${disk_targets[@]}" || return 1
  fi
  return 0
}

# 2. Plaintext leak scan
if [ "$do_check_files" = true ]; then
  hits=$(run_scans L && run_scans W) || exit 1

  if [ -n "$hits" ]; then
    report=$(awk -F'\t' '
      NR == FNR {
        if ($1 == "M") origins[$2] = ($2 in origins) ? (origins[$2] ", " $3) : $3
        next
      }
      {
        if (!match($0, /:[0-9]+:/)) next
        loc = substr($0, 1, RSTART + RLENGTH - 2)
        content = tolower(substr($0, RSTART + RLENGTH))
        for (n in origins) {
          if (index(content, n) > 0 && !((loc SUBSEP n) in seen)) {
            seen[loc SUBSEP n] = 1
            print loc "\t" origins[n]
          }
        }
      }
    ' <(printf '%s\n' "$analysis") <(printf '%s\n' "$hits") | sort -u)

    if [ -n "$report" ]; then
      echo -e "${RED}[ERROR] SOPS secret leak detected in plaintext file(s)!${NC}" >&2
      echo "Never hardcode values from secrets/credentials*.sops.yaml in plaintext files or tests." >&2
      echo "Violating locations (secret values redacted per STD-CI-33):" >&2
      while IFS=$'\t' read -r file_line sops_origin; do
        [ -n "$file_line" ] && echo "  - ${file_line} (matches ${sops_origin})" >&2
      done < <(printf '%s\n' "$report")
      exit_code=1
    fi
  fi
fi

exit "$exit_code"
