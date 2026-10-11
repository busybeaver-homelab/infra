#!/usr/bin/env bats
# Tests for scripts/generate-tf-docs.sh

load 'helpers/test_helper'

GEN_DOCS_SCRIPT="${SCRIPTS_DIR}/generate-tf-docs.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "generate-tf-docs.sh exists and is executable" {
  [ -f "${GEN_DOCS_SCRIPT}" ]
  [ -x "${GEN_DOCS_SCRIPT}" ]
}

@test "generate-tf-docs.sh contains valid bash shebang" {
  run head -n 1 "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^#\!/usr/bin/env[[:space:]]+bash ]]
}

@test "generate-tf-docs.sh passes shellcheck" {
  run shellcheck "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh passes shfmt check" {
  run shfmt -d -i 2 -ci "${GEN_DOCS_SCRIPT}"
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

  run env PATH="${mock_bin_dir}:${PATH}" bash "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
  [ -f "${mock_log}" ]
  run grep -E "\-\-config \.terraform-docs\.yml infrastructure/oci" "${mock_log}"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh runs cleanly on non-existent path" {
  run bash "${GEN_DOCS_SCRIPT}" "${BATS_TMPDIR}/nonexistent.tf"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh ignores non-infrastructure files" {
  local mock_other="${BATS_TMPDIR}/other_dir/main.tf"
  mkdir -p "$(dirname "$mock_other")"
  touch "$mock_other"

  run bash "${GEN_DOCS_SCRIPT}" "$mock_other"
  [ "$status" -eq 0 ]
}

@test "generate-tf-docs.sh extracts directory name from an infrastructure file argument" {
  local mock_infra="${REPO_ROOT}/infrastructure/azure/main.tf"
  [ -f "$mock_infra" ] || skip "infrastructure/azure/main.tf does not exist"

  # Pass existing infrastructure file path
  run bash "${GEN_DOCS_SCRIPT}" "$mock_infra"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "infrastructure/azure" ]]
}

@test "generate-tf-docs.sh harmonizes generated readme files with oxfmt" {
  run grep -E "run-oxfmt\.sh" "${GEN_DOCS_SCRIPT}"
  [ "$status" -eq 0 ]
}
