#!/usr/bin/env bash

set -euo pipefail

# Script to verify schema parity between production and CI SOPS secrets files:
# 1. Extracts YAML key paths (ignoring .sops metadata) without decrypting secrets.
# 2. Ensures the key hierarchies of both files match identically.
# 3. Exits 0 on match, exits 1 with a diff on mismatch.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Locate yq command
if command -v yq >/dev/null 2>&1; then
  YQ_CMD=(yq)
else
  YQ_CMD=(mise exec -- yq)
fi

repo_root=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  repo_root=$(git rev-parse --show-toplevel)
fi

PROD_FILE="${1:-}"
CI_FILE="${2:-}"

if [ -z "$PROD_FILE" ]; then
  if [ -n "$repo_root" ] && [ -f "${repo_root}/secrets/credentials.sops.yaml" ]; then
    PROD_FILE="${repo_root}/secrets/credentials.sops.yaml"
  else
    PROD_FILE="secrets/credentials.sops.yaml"
  fi
fi

if [ -z "$CI_FILE" ]; then
  if [ -n "$repo_root" ] && [ -f "${repo_root}/secrets/credentials.ci.sops.yaml" ]; then
    CI_FILE="${repo_root}/secrets/credentials.ci.sops.yaml"
  else
    CI_FILE="secrets/credentials.ci.sops.yaml"
  fi
fi

if [ ! -f "$PROD_FILE" ]; then
  echo -e "${RED}[ERROR] Primary credentials file not found: $PROD_FILE${NC}" >&2
  exit 1
fi

if [ ! -f "$CI_FILE" ]; then
  echo -e "${RED}[ERROR] Secondary credentials file not found: $CI_FILE${NC}" >&2
  exit 1
fi

extract_keys() {
  local target="$1"
  local raw
  if ! raw=$("${YQ_CMD[@]}" 'del(.sops) | [.. | select(tag != "!!map") | path | join(".")] | .[]' "$target"); then
    echo -e "${RED}[ERROR] Failed to parse YAML in $target${NC}" >&2
    return 1
  fi
  if [[ -z "${raw//[[:space:]]/}" ]]; then
    echo -e "${RED}[ERROR] No secret keys found in $target${NC}" >&2
    return 1
  fi
  printf '%s\n' "$raw" | sort -u
}

prod_keys=$(extract_keys "$PROD_FILE")
ci_keys=$(extract_keys "$CI_FILE")

if [ "$prod_keys" = "$ci_keys" ]; then
  echo -e "${GREEN}[INFO] Schema parity verified between $(basename "$PROD_FILE") and $(basename "$CI_FILE").${NC}"
  exit 0
else
  echo -e "${RED}[ERROR] Schema parity violation between $(basename "$PROD_FILE") and $(basename "$CI_FILE")!${NC}" >&2
  echo -e "Key difference (- $PROD_FILE, + $CI_FILE):" >&2
  diff -u <(echo "$prod_keys") <(echo "$ci_keys") >&2 || true
  exit 1
fi
