#!/usr/bin/env bash
# scripts/check-sops-secret-leaks.sh
#
# Prevents SOPS-encrypted secrets from leaking into plaintext repository files
# and enforces secret value disjointness between production and CI SOPS files:
#   - secrets/credentials.sops.yaml (production, GPG-encrypted)
#   - secrets/credentials.ci.sops.yaml (CI decoy, Age-encrypted)
#
# Security & Log Hygiene (AGENTS.md §1, STD-CI-33):
#   - NEVER prints decrypted secret values or raw matching line contents.
#   - Reports only <file>:<line> and <sops_file>:<yaml_key_path>.
#   - Uses a private (umask 077) temporary directory cleaned up via EXIT trap.

set -euo pipefail

if { ! command -v sops >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; } && [ -d "${HOME:-}/.local/share/mise/shims" ]; then
  export PATH="${HOME}/.local/share/mise/shims:${PATH}"
fi

RED='\033[0;31m'
NC='\033[0m'

PROD_SOPS_FILE="${PROD_SOPS_FILE:-secrets/credentials.sops.yaml}"
CI_SOPS_FILE="${CI_SOPS_FILE:-secrets/credentials.ci.sops.yaml}"

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

is_git=false
repo_root=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git=true
  repo_root=$(git rev-parse --show-toplevel)
fi

scan_targets=()
if [ "$do_check_files" = true ]; then
  if [ "$do_all_files" = true ] && [ "$is_git" = true ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && file_args+=("$f")
    done < <(git ls-files)
  elif [ ${#file_args[@]} -eq 0 ] && [ "$is_git" = true ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && file_args+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACM)
  fi

  if [ ${#file_args[@]} -gt 0 ]; then
    for file in "${file_args[@]}"; do
      normalized_file="${file#./}"
      if [ -n "$repo_root" ]; then
        normalized_file="${normalized_file#"$repo_root"/}"
      fi

      # Skip SOPS-encrypted files
      if [[ "$normalized_file" == *.sops.* ]] || [[ "$normalized_file" == *.sops.yaml ]] || [[ "$normalized_file" == *.sops.yml ]] || [[ "$normalized_file" == *.sops.json ]]; then
        continue
      fi

      # Skip git-crypt encrypted directories (docs/*, backups/*) and production mesh ACL template
      if [[ "$normalized_file" == docs/* ]] || [[ "$normalized_file" == */docs/* ]] ||
        [[ "$normalized_file" == backups/* ]] || [[ "$normalized_file" == */backups/* ]] ||
        [ "$normalized_file" = "infrastructure/mesh/policy.hujson.tftpl" ] || [[ "$normalized_file" == */infrastructure/mesh/policy.hujson.tftpl ]]; then
        continue
      fi

      # Skip missing files, directories, or symlinks to directories
      if [ ! -f "$file" ] || [ -d "$file" ]; then
        continue
      fi

      scan_targets+=("$file")
    done
  fi
fi

# Fast exit if only checking files and no eligible plaintext files are staged/passed
if [ "$do_check_disjointness" = false ] && [ ${#scan_targets[@]} -eq 0 ]; then
  exit 0
fi

umask 077
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

extracted_tsv="${tmp_dir}/extracted.tsv"
: >"$extracted_tsv"

has_age_key_configured() {
  if [ -n "${SOPS_AGE_KEY:-}" ] || [ -n "${SOPS_AGE_KEY_FILE:-}" ]; then
    return 0
  fi
  local xdg_keys="${XDG_CONFIG_HOME:-${HOME:-}/.config}/sops/age/keys.txt"
  local mac_keys="${HOME:-}/Library/Application Support/sops/age/keys.txt"
  if [ -f "$xdg_keys" ] || [ -f "$mac_keys" ]; then
    return 0
  fi
  return 1
}

extract_sops_leaves() {
  local sops_file="$1"
  local label="$2"
  local json_file="${tmp_dir}/decrypted.json"

  if [ ! -f "$sops_file" ]; then
    echo -e "${RED}[ERROR] Failed to decrypt ${label}: file not found.${NC}" >&2
    return 1
  fi

  if ! sops --decrypt --output-type json "$sops_file" >"$json_file" 2>/dev/null; then
    rm -f "$json_file"
    echo -e "${RED}[ERROR] Failed to decrypt ${label}. Ensure your GPG/Age keys are available (fail-closed policy).${NC}" >&2
    return 1
  fi

  jq -r --arg src "$label" '
    paths(scalars) as $p
    | select(($p | first) != "sops")
    | (getpath($p) | select(type == "string")) as $val
    | ($p | map(tostring) | join(".")) as $path
    | (($val | contains("\n")) | tostring) as $multi
    | ($val | gsub("\r"; "") | split("\n")[]) as $line
    | select(($line | length) > 0)
    | "\($src)\t\($path)\t\($multi)\t\($line)"
  ' "$json_file" >>"$extracted_tsv"

  rm -f "$json_file"
}

prod_decrypted=false
ci_decrypted=false

if [ "${CI:-false}" = "true" ]; then
  # In CI, production GPG key is not present; decrypt prod SOPS only if key happens to be available
  if [ -f "$PROD_SOPS_FILE" ] && sops --decrypt --output-type json "$PROD_SOPS_FILE" >"${tmp_dir}/prod_probe.json" 2>/dev/null; then
    rm -f "${tmp_dir}/prod_probe.json"
    extract_sops_leaves "$PROD_SOPS_FILE" "secrets/credentials.sops.yaml"
    prod_decrypted=true
  fi

  # In CI, decrypt CI SOPS file whenever an Age key is configured; fail closed if decryption fails
  if has_age_key_configured; then
    extract_sops_leaves "$CI_SOPS_FILE" "secrets/credentials.ci.sops.yaml"
    ci_decrypted=true
  fi
else
  # Local environment (CI != true): strictly fail-closed on both SOPS files
  extract_sops_leaves "$PROD_SOPS_FILE" "secrets/credentials.sops.yaml"
  prod_decrypted=true
  extract_sops_leaves "$CI_SOPS_FILE" "secrets/credentials.ci.sops.yaml"
  ci_decrypted=true
fi

needles_file="${tmp_dir}/needles.txt"
needle_map_file="${tmp_dir}/needle_map.tsv"
collisions_file="${tmp_dir}/collisions.txt"
: >"$needles_file"
: >"$needle_map_file"
: >"$collisions_file"

awk -F'\t' \
  -v need_file="$needles_file" \
  -v map_file="$needle_map_file" \
  -v col_file="$collisions_file" \
  -v check_disjoint="$do_check_disjointness" \
  -v prod_ok="$prod_decrypted" \
  -v ci_ok="$ci_decrypted" '
function is_allowlisted_path(p) {
  if (p == "is_production" || p == "gcp.region" || p == "gcp.zone" || p == "gcp.breakglass_user" || p == "oci.region" || p == "oci.breakglass_user" || p == "cloudflare_restic.bucket" || p == "github.owner") return 1
  if (p ~ /^github\.config\.repositories\.[^.]+\.(name|description)$/) return 1
  if (p ~ /^github\.config\.repositories\.[^.]+\.topics\.[0-9]+$/) return 1
  if (p ~ /^cloudflare\.config\.zero_trust\.split_tunnel_excludes\.[0-9]+\.(address|description)$/) return 1
  if (p ~ /\.permission_groups\.[0-9]+$/) return 1
  if (p ~ /\.(type|effect|field|action|proxied|ttl|priority|enabled|locked|auto_init|visibility|vulnerability_alerts|delete_branch_on_merge|web_commit_signoff_required|default_branch|squash_merge_commit_title|squash_merge_commit_message)$/) return 1
  return 0
}

function is_non_secret_placeholder(val,    low) {
  low = tolower(val)
  if (val ~ /^-----BEGIN / || val ~ /^-----END /) return 1
  if (val ~ /<[^>]+>/) return 1
  if (low ~ /^(placeholder|changeme|dummy|todo|none|null|disabled)$/) return 1
  if (low == "https://storage.googleapis.com" || low == "ci-validation-dummy-passphrase-32ch" || low == "012345-6789ab-cdef01") return 1
  if (val ~ /^192\.0\.2\.[0-9]+$/) return 1
  if (low ~ /(^|\.|@|-)example(\.|-|$)/) return 1
  if (low ~ /^0{16,}[0-9a-f]{0,4}$/) return 1
  if (low ~ /^decoy[-_.]/) return 1
  return 0
}

function emit_raw_needle(raw) {
  if (!(raw in seen_raw_needle)) {
    seen_raw_needle[raw] = 1
    print raw > need_file
  }
}

function add_needle(n, src_path,    low, up) {
  low = tolower(n)
  up = toupper(n)
  emit_raw_needle(n)
  emit_raw_needle(low)
  emit_raw_needle(up)
  if (!((low SUBSEP src_path) in seen_map)) {
    seen_map[low SUBSEP src_path] = 1
    print low "\t" src_path > map_file
  }
}

{
  src = $1
  path = $2
  multi = $3
  line = $4
  for (i = 5; i <= NF; i++) {
    line = line "\t" $i
  }

  # Accumulate full leaf values for Prod-vs-CI disjointness check
  if (src == "secrets/credentials.sops.yaml") {
    prod_paths[path] = 1
    prod_full[path] = (path in prod_full) ? (prod_full[path] "\n" line) : line
  } else if (src == "secrets/credentials.ci.sops.yaml") {
    ci_paths[path] = 1
    ci_full[path] = (path in ci_full) ? (ci_full[path] "\n" line) : line
  }

  if (is_allowlisted_path(path)) next

  # Trim leading/trailing whitespace on individual lines
  gsub(/^[ \t]+|[ \t]+$/, "", line)
  if (is_non_secret_placeholder(line)) next

  if (multi == "true") {
    if (length(line) < 24) next
  } else {
    if (length(line) < 8) next
  }

  src_path = src ":" path
  add_needle(line, src_path)

  # Derived needle: Age secret key bech32 body without AGE-SECRET-KEY-1 prefix
  if (toupper(line) ~ /^AGE-SECRET-KEY-1[A-Z0-9]+$/ && length(line) > 24) {
    add_needle(substr(line, 17), src_path)
  }
}

END {
  if (check_disjoint == "true" && prod_ok == "true" && ci_ok == "true") {
    for (p in prod_paths) {
      if ((p in ci_paths) && !is_allowlisted_path(p)) {
        if (length(prod_full[p]) > 0 && tolower(prod_full[p]) == tolower(ci_full[p])) {
          if (!is_non_secret_placeholder(prod_full[p])) {
            print p > col_file
          }
        }
      }
    }
  }
}
' "$extracted_tsv"

exit_code=0

# 1. Check Prod-vs-CI SOPS Disjointness Results
if [ "$do_check_disjointness" = true ] && [ -s "$collisions_file" ]; then
  echo -e "${RED}[ERROR] SOPS Disjointness violation: secrets/credentials.ci.sops.yaml contains production secret value(s)!${NC}" >&2
  echo "The following YAML key path(s) have identical values in both SOPS files:" >&2
  while IFS= read -r col_path; do
    [ -z "$col_path" ] && continue
    echo "  - ${col_path}" >&2
  done < <(sort -u "$collisions_file")
  echo "Replace the value(s) in secrets/credentials.ci.sops.yaml with synthetic decoy values." >&2
  exit_code=1
fi

# 2. Check Target Plaintext Files for Leaked SOPS Values
# Note: rg (ripgrep) uses SIMD Aho-Corasick and skips binary files (such as git-crypt locked files) by default;
# fallback grep -I -F also skips binary files starting with \0GITCRYPT\0.
if [ "$do_check_files" = true ] && [ ${#scan_targets[@]} -gt 0 ] && [ -s "$needles_file" ]; then
  grep_hits="${tmp_dir}/grep_hits.txt"
  if command -v rg >/dev/null 2>&1; then
    rg --no-config -F -i -n --with-filename --no-heading --color=never -f "$needles_file" "${scan_targets[@]}" >"$grep_hits" 2>/dev/null || true
  else
    LC_ALL=C grep -I -F -n -H -f "$needles_file" "${scan_targets[@]}" >"$grep_hits" 2>/dev/null || true
  fi

  if [ -s "$grep_hits" ]; then
    report_file="${tmp_dir}/report.txt"
    awk -F'\t' '
      NR == FNR {
        needle = $1
        src_path = $2
        needles[needle] = (needle in needles) ? (needles[needle] ", " src_path) : src_path
        next
      }
      {
        raw = $0
        c1 = index(raw, ":")
        if (c1 == 0) next
        fname = substr(raw, 1, c1 - 1)
        rest = substr(raw, c1 + 1)
        c2 = index(rest, ":")
        if (c2 == 0) next
        lnum = substr(rest, 1, c2 - 1)
        content_low = tolower(substr(rest, c2 + 1))

        for (n in needles) {
          if (index(content_low, n) > 0) {
            key = fname ":" lnum "\t" needles[n]
            if (!(key in reported)) {
              reported[key] = 1
              print key
            }
          }
        }
      }
    ' "$needle_map_file" "$grep_hits" | sort -u >"$report_file"

    if [ -s "$report_file" ]; then
      echo -e "${RED}[ERROR] SOPS secret leak detected in plaintext file(s)!${NC}" >&2
      echo "Never hardcode values from secrets/credentials*.sops.yaml in plaintext files or tests." >&2
      echo "Violating locations (secret values redacted per STD-CI-33):" >&2
      while IFS=$'\t' read -r file_line sops_origin; do
        [ -z "$file_line" ] && continue
        echo "  - ${file_line} (matches ${sops_origin})" >&2
      done <"$report_file"
      exit_code=1
    fi
  fi
fi

exit "$exit_code"
