#!/usr/bin/env bats
# Parity and enforcement tests for OpenTofu core version pins (STD-OT-08, STD-OT-09, STD-OT-10, R2-REN-02)

bats_require_minimum_version 1.5.0

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "every OpenTofu module directory has opentofu.tofu and no .tf/.tofu basename collision (STD-OT-08, STD-OT-10)" {
  local found=0
  for dir in "${REPO_ROOT}"/infrastructure/*/ "${REPO_ROOT}"/infrastructure/*/modules/*/; do
    [ -d "$dir" ] || continue
    compgen -G "${dir}*.tf" >/dev/null || continue
    found=$((found + 1))

    if [ ! -f "${dir}opentofu.tofu" ]; then
      echo "Missing opentofu.tofu in ${dir}" >&2
      return 1
    fi

    for tofu_file in "${dir}"*.tofu; do
      [ -f "$tofu_file" ] || continue
      local base
      base="$(basename "$tofu_file" .tofu)"
      if [ -f "${dir}${base}.tf" ]; then
        echo "Collision between ${base}.tofu and ${base}.tf in ${dir}" >&2
        return 1
      fi
    done
  done

  [[ "$found" -ge 12 ]] || false
}

@test "every opentofu.tofu required_version matches mise.toml opentofu major.minor (STD-OT-08)" {
  local mise_version
  mise_version="$(sed -nE 's/^"aqua:opentofu\/opentofu"[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+).*"/\1/p' "${REPO_ROOT}/mise.toml")"
  [[ -n "$mise_version" ]] || false

  local checked=0
  for tofu_file in "${REPO_ROOT}"/infrastructure/*/opentofu.tofu "${REPO_ROOT}"/infrastructure/*/modules/*/opentofu.tofu; do
    [ -f "$tofu_file" ] || continue
    checked=$((checked + 1))

    local pin_minor
    pin_minor="$(sed -nE 's/^[[:space:]]*required_version[[:space:]]*=[[:space:]]*"[^0-9]*([0-9]+\.[0-9]+).*"/\1/p' "$tofu_file")"
    if [[ "$pin_minor" != "$mise_version" ]]; then
      echo "Version mismatch in ${tofu_file}: got '${pin_minor}', expected '${mise_version}' from mise.toml" >&2
      return 1
    fi
  done

  [[ "$checked" -ge 12 ]] || false
}

@test "no versions.tf pins a HashiCorp Terraform 1.16.x release or diverges from opentofu.tofu (STD-OT-09)" {
  run grep -rnE 'required_version[[:space:]]*=[[:space:]]*"[^"]*1\.16\.' "${REPO_ROOT}/infrastructure"
  [[ "$status" -eq 1 ]] || false

  for versions_file in "${REPO_ROOT}"/infrastructure/*/versions.tf "${REPO_ROOT}"/infrastructure/*/modules/*/versions.tf; do
    [ -f "$versions_file" ] || continue
    local dir
    dir="$(dirname "$versions_file")"
    local tf_req tofu_req
    tf_req="$(sed -nE 's/^[[:space:]]*required_version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "$versions_file")"
    tofu_req="$(sed -nE 's/^[[:space:]]*required_version[[:space:]]*=[[:space:]]*"([^"]+)"/\1/p' "${dir}/opentofu.tofu")"
    if [[ -n "$tf_req" && "$tf_req" != "$tofu_req" ]]; then
      echo "Divergent required_version in ${versions_file} ('${tf_req}') vs ${dir}/opentofu.tofu ('${tofu_req}')" >&2
      return 1
    fi
  done
}

@test "renovate config disables terraform required_version management (STD-OT-14, R2-REN-02)" {
  local renovate_file=""
  if [ -f "${REPO_ROOT}/.github/renovate.json5" ]; then
    renovate_file="${REPO_ROOT}/.github/renovate.json5"
  elif [ -f "${REPO_ROOT}/.github/renovate.json" ]; then
    renovate_file="${REPO_ROOT}/.github/renovate.json"
  fi
  [[ -n "$renovate_file" ]] || false

  run grep -E 'required_version' "$renovate_file"
  [[ "$status" -eq 0 ]] || false
}

@test "OpenTofu enforces required_version in opentofu.tofu on incompatible constraint (STD-OT-08)" {
  cat >"${BATS_TMPDIR}/opentofu.tofu" <<'EOF'
terraform {
  required_version = "~> 99.0.0"
}
EOF

  run mise exec -- tofu -chdir="${BATS_TMPDIR}" init -backend=false
  [[ "$status" -ne 0 ]] || false
  [[ "$output" == *"Unsupported"* || "$output" == *"Incompatible"* || "$output" == *"required_version"* ]] || false
}

@test "lefthook globs for tofu-fmt, tofu-lint, and tofu-validate include both .tf and .tofu files" {
  local lefthook_file="${REPO_ROOT}/lefthook.yml"
  run awk '
    /^    tofu-fmt:/ { in_fmt=1; next }
    in_fmt && /^    [a-z]/ { in_fmt=0 }
    in_fmt && /glob:[[:space:]]*"\*\.{tf,tofu}"/ { fmt_ok=1 }
    /^    tofu-lint:/ { in_lint=1; next }
    in_lint && /^    [a-z]/ { in_lint=0 }
    in_lint && /glob:[[:space:]]*"infrastructure\/\*\*\/\*\.{tf,tofu}"/ { lint_ok=1 }
    /^    tofu-validate:/ { in_val=1; next }
    in_val && /^    [a-z]/ { in_val=0 }
    in_val && /glob:[[:space:]]*"infrastructure\/\*\*\/\*\.{tf,tofu}"/ { val_ok=1 }
    END { exit(fmt_ok && lint_ok && val_ok ? 0 : 1) }
  ' "$lefthook_file"
  [[ "$status" -eq 0 ]] || false
}

