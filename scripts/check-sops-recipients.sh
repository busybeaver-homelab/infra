#!/usr/bin/env bash
# scripts/check-sops-recipients.sh
#
# Guards which keys the two canonical SOPS files are encrypted to (R2-SEC-01 step 5).
# Every recipient (age public key or PGP fingerprint) must be listed in
# .sops-recipients.allowlist for that file:
#   - the current files and the .sops.yaml creation rules may use only `active` recipients;
#   - with --history, every committed revision may use `active` or `retired` recipients.
# An unknown recipient means someone could decrypt a revision without being on the list.
#
# Allowlist format (one per line; `#` starts a comment):
#   <recipient> <status: active|retired> <file: prod|ci>
#
# Usage: check-sops-recipients.sh [--history]
#   REPO_ROOT overrides the repository root (tests).
# Output names files, revisions and a recipient prefix only; recipients are public keys.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
cd "$REPO_ROOT"

ALLOWLIST=".sops-recipients.allowlist"
HISTORY=false
[ "${1:-}" = "--history" ] && HISTORY=true

file_for() { # bash 3.2 compatible (no associative arrays)
  case "$1" in
    prod) echo "secrets/credentials.sops.yaml" ;;
    ci) echo "secrets/credentials.ci.sops.yaml" ;;
  esac
}

[ -f "$ALLOWLIST" ] || {
  echo "ERROR: ${ALLOWLIST} is missing" >&2
  exit 1
}

# Prints "<recipient>" for every age and PGP recipient in a SOPS document on stdin.
recipients() {
  yq -r '[
    (.sops.age // [])[].recipient,
    (.sops.pgp // [])[].fp,
    (.sops.key_groups // [])[] | ((.age // [])[].recipient, (.pgp // [])[].fp)
  ] | .[] | select(. != null)' 2>/dev/null
}

# allowed <scope> <statuses regex> <recipient>
allowed() {
  awk -v s="$1" -v st="$2" -v r="$3" '
    { sub(/#.*/, "") }
    NF >= 3 && $1 == r && $3 == s && $2 ~ ("^(" st ")$") { found = 1 }
    END { exit found ? 0 : 1 }' "$ALLOWLIST"
}

short() { printf '%s…' "${1:0:12}"; }

errors=0

# 1. Current files: active recipients only.
for scope in prod ci; do
  file="$(file_for "$scope")"
  [ -f "$file" ] || continue
  while IFS= read -r r; do
    if ! allowed "$scope" "active" "$r"; then
      echo "ERROR: ${file} is encrypted to a recipient that is not active for ${scope}: $(short "$r")" >&2
      errors=$((errors + 1))
    fi
  done < <(recipients <"$file")
done

# 2. .sops.yaml creation rules: active recipients only.
# shellcheck disable=SC2016 # $p is a yq variable, not a shell expansion
while IFS=$'\t' read -r regex r; do
  scope=""
  [[ "secrets/credentials.sops.yaml" =~ $regex ]] && scope=prod
  [[ "secrets/credentials.ci.sops.yaml" =~ $regex ]] && scope=ci
  [ -n "$scope" ] || continue
  if ! allowed "$scope" "active" "$r"; then
    echo "ERROR: .sops.yaml rule for ${scope} names a recipient that is not active: $(short "$r")" >&2
    errors=$((errors + 1))
  fi
done < <(yq -r '.creation_rules[] | .path_regex as $p
  | [(.key_groups // [])[] | ((.age // [])[], (.pgp // [])[]), (.age // "" | split(",")[]), (.pgp // "" | split(",")[])][]
  | select(. != "") | [$p, .] | @tsv' .sops.yaml)

# 3. History: every committed revision, active or retired recipients.
if [ "$HISTORY" = true ]; then
  for scope in prod ci; do
    file="$(file_for "$scope")"
    while IFS= read -r rev; do
      while IFS= read -r r; do
        if ! allowed "$scope" "active|retired" "$r"; then
          echo "ERROR: ${file}@${rev} is encrypted to an unlisted recipient: $(short "$r")" >&2
          errors=$((errors + 1))
        fi
      done < <(git show --no-textconv "${rev}:${file}" 2>/dev/null | recipients)
    done < <(git log --all --format=%h -- "$file")
  done
fi

if [ "$errors" -gt 0 ]; then
  echo "SOPS recipient check failed (${errors} problem(s)); see ${ALLOWLIST}." >&2
  exit 1
fi
echo "SOPS recipients OK ($([ "$HISTORY" = true ] && echo "current files and history" || echo "current files"))."
