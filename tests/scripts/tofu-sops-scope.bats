#!/usr/bin/env bats
# Regression tests for OpenTofu SOPS scope isolation (R2-TF-02 / REV2-P1-3).
#
# Ensures:
#   1. No `data "sops_file"` exists anywhere under `infrastructure/`.
#   2. Every `extract` given to `scripts/sops-subtree.sh` across `infrastructure/**/*.tf`
#      is either a `["<root>"]["config"]` subtree (`^"\[\"[a-z0-9_]+\"\]\[\"config\"\]"$`)
#      or on the explicit residual-limitation allowlist:
#        - `["github"]["ci_age_key"]` (integrations/github 6.13.0 has no write-only secret attribute)
#   3. `infrastructure/github` resolves `github_token` and `github_owner` exclusively from
#      variables or `ephemeral.sops_file.secrets`, never from `data.external`.

load 'helpers/test_helper'

@test "no data sops_file resource exists under infrastructure/" {
  run grep -rn -E '^[[:space:]]*data[[:space:]]+"sops_file"' "${REPO_ROOT}/infrastructure" --include='*.tf'
  [ "$status" -ne 0 ]
}

@test "every sops-subtree.sh extract under infrastructure/ is config-only or on the documented allowlist" {
  local line value unescaped
  local -a violations=()

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    value="${line#*=}"
    # Strip leading/trailing whitespace and inline comments
    value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*(#.*)?$//')"
    # Unescape HCL string quotes: "[\"a\"][\"b\"]" -> ["a"]["b"]
    unescaped="${value#\"}"
    unescaped="${unescaped%\"}"
    unescaped="${unescaped//\\\"/\"}"

    if [[ "$unescaped" =~ ^\[\"[a-z0-9_]+\"\]\[\"config\"\]$ ]]; then
      continue
    fi

    case "$unescaped" in
      '["github"]["ci_age_key"]')
        continue
        ;;
      *)
        violations+=("${line} (parsed: ${unescaped})")
        ;;
    esac
  done < <(grep -rn -E '^[[:space:]]*extract[[:space:]]*=' "${REPO_ROOT}/infrastructure" --include='*.tf')

  if (( ${#violations[@]} > 0 )); then
    printf 'Disallowed sops-subtree extract(s) found:\n' >&2
    printf '  %s\n' "${violations[@]}" >&2
    return 1
  fi
}

@test "infrastructure/github resolves github_token and github_owner from ephemeral sops_file, not data.external" {
  run grep -E 'github_(token|owner)[[:space:]]*=.*(github_config|github_data|sops_github)' "${REPO_ROOT}/infrastructure/github/locals.tf"
  [ "$status" -ne 0 ]

  run grep -E 'github_token[[:space:]]*=.*local\.sops_ephemeral\.github\.token' "${REPO_ROOT}/infrastructure/github/locals.tf"
  [ "$status" -eq 0 ]

  run grep -E 'github_owner[[:space:]]*=.*local\.sops_ephemeral\.github\.owner' "${REPO_ROOT}/infrastructure/github/locals.tf"
  [ "$status" -eq 0 ]
}
