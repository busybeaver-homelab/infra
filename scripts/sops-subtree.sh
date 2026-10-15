#!/usr/bin/env bash
# scripts/sops-subtree.sh
#
# OpenTofu external data source helper (R2-TF-02 / REV2-P1-3).
# Decrypts only a single domain subtree from a SOPS file via `sops -d --extract`
# so the full decrypted SOPS document is never persisted in OpenTofu state.
#
# Input (stdin JSON from `data "external"`):
#   {"file": "<path-to-sops-file>", "extract": "[\"domain\"][\"subtree\"]"}
# Output (stdout JSON for `data "external"`):
#   {"json": "<compact JSON string of extracted subtree>"}

set -euo pipefail

input="$(cat)"
if [[ -z "${input}" ]]; then
  echo "ERROR: empty stdin query for sops-subtree.sh" >&2
  exit 1
fi

file="$(printf '%s' "${input}" | jq -er '.file // empty')" || {
  echo "ERROR: missing required query key 'file'" >&2
  exit 1
}
extract="$(printf '%s' "${input}" | jq -er '.extract // empty')" || {
  echo "ERROR: missing required query key 'extract'" >&2
  exit 1
}

if [[ ! -f "${file}" ]]; then
  echo "ERROR: SOPS file not found: ${file}" >&2
  exit 1
fi

subtree_yaml="$(sops -d --extract "${extract}" "${file}")"
subtree_json="$(printf '%s\n' "${subtree_yaml}" | yq -o=json -I=0 '.')"
jq -cn --arg json "${subtree_json}" '{json: $json}'
