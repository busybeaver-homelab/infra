#!/usr/bin/env bats
# Tests for scripts/generate-tf-docs.sh

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "generate-tf-docs.sh exists and is executable" {
  local script="${REPO_ROOT}/scripts/generate-tf-docs.sh"
  [ -f "$script" ]
  [ -x "$script" ]
}

@test "generate-tf-docs.sh contains valid bash shebang" {
  local script="${REPO_ROOT}/scripts/generate-tf-docs.sh"
  run head -n 1 "$script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^#\!/usr/bin/env[[:space:]]+bash ]]
}

@test "generate-tf-docs.sh passes shellcheck" {
  run shellcheck "${REPO_ROOT}/scripts/generate-tf-docs.sh"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh passes shfmt check" {
  run shfmt -d -i 2 -ci "${REPO_ROOT}/scripts/generate-tf-docs.sh"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh finds all infrastructure module directories" {
  run bash -c "cd '${REPO_ROOT}' && find infrastructure -type f -name '*.tf' -not -path '*/.*' -exec dirname {} \; | sort -u"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "infrastructure/azure" ]]
  [[ "$output" =~ "infrastructure/cloudflare" ]]
  [[ "$output" =~ "infrastructure/gcp" ]]
  [[ "$output" =~ "infrastructure/github" ]]
  [[ "$output" =~ "infrastructure/homelab" ]]
  [[ "$output" =~ "infrastructure/monitoring" ]]
  [[ "$output" =~ "infrastructure/oci" ]]
}

@test "generate-tf-docs.sh invokes terraform-docs with config in dry-run/mock mode" {
  local mock_bin_dir="${BATS_TMPDIR}/bin"
  mkdir -p "$mock_bin_dir"
  local mock_log="${BATS_TMPDIR}/terraform-docs.log"

  cat <<EOF > "${mock_bin_dir}/terraform-docs"
#!/usr/bin/env bash
echo "\$@" >> "${mock_log}"
exit 0
EOF
  chmod +x "${mock_bin_dir}/terraform-docs"

  run env PATH="${mock_bin_dir}:${PATH}" bash "${REPO_ROOT}/scripts/generate-tf-docs.sh"
  [ "$status" -eq 0 ]
  [ -f "${mock_log}" ]
  run grep -E "\-\-config \.terraform-docs\.yml infrastructure/oci" "${mock_log}"
  [ "$status" -eq 0 ]
}
