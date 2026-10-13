#!/usr/bin/env bats
# Tests for configuration/roles/base_ubuntu_server/files/oci-fetch-secrets.sh

load 'helpers/test_helper'

SCRIPT_PATH="${REPO_ROOT}/configuration/roles/base_ubuntu_server/files/oci-fetch-secrets.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "oci-fetch-secrets.sh is shellcheck compliant" {
  [ -f "${SCRIPT_PATH}" ]
  run shellcheck "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "oci-fetch-secrets.sh displays help with --help" {
  run bash "${SCRIPT_PATH}" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage:"
  echo "$output" | grep -q -- "--dest"
  echo "$output" | grep -q -- "--dry-run"
}

@test "oci-fetch-secrets.sh creates target dir with 0700 permissions in dry-run mode" {
  local target_dir="${BATS_TMPDIR}/run_secrets"
  run bash "${SCRIPT_PATH}" --dry-run --dest "${target_dir}"
  [ "$status" -eq 0 ]
  [ -d "${target_dir}" ]
  mode=$(stat -c "%a" "${target_dir}" 2>/dev/null || stat -f "%Lp" "${target_dir}")
  [ "$mode" -eq 700 ]
}

@test "oci-fetch-secrets.sh respects SECRETS_DEST_DIR environment variable" {
  local target_dir="${BATS_TMPDIR}/env_secrets"
  SECRETS_DEST_DIR="${target_dir}" run bash "${SCRIPT_PATH}" --dry-run
  [ "$status" -eq 0 ]
  [ -d "${target_dir}" ]
  mode=$(stat -c "%a" "${target_dir}" 2>/dev/null || stat -f "%Lp" "${target_dir}")
  [ "$mode" -eq 700 ]
}

@test "oci-fetch-secrets.sh decodes and writes secrets with 0400 permissions via mock oci cli" {
  local mock_bin="${BATS_TMPDIR}/mock_bin"
  local target_dir="${BATS_TMPDIR}/secrets"
  mkdir -p "${mock_bin}"

  # Create mock oci CLI
  cat <<'MOCK_EOF' > "${mock_bin}/oci"
#!/usr/bin/env bash
# Echo base64-encoded secret value
echo "bW9jay1zZWNyZXQtdmFsdWUK"
MOCK_EOF
  chmod +x "${mock_bin}/oci"

  prepend_path "${mock_bin}"

  run bash "${SCRIPT_PATH}" --dest "${target_dir}" --vault-id "ocid1.vault.oc1..mock" restic_password
  [ "$status" -eq 0 ]
  [ -f "${target_dir}/restic_password" ]

  # Check file content matches decoded mock value
  content=$(cat "${target_dir}/restic_password")
  [ "$content" = "mock-secret-value" ]

  # Check file permission is strictly 0400
  file_mode=$(stat -c "%a" "${target_dir}/restic_password" 2>/dev/null || stat -f "%Lp" "${target_dir}/restic_password")
  [ "$file_mode" -eq 400 ]
}

@test "oci-fetch-secrets.sh retries and fails closed if OCI CLI consistently errors" {
  local mock_bin="${BATS_TMPDIR}/mock_bin"
  local target_dir="${BATS_TMPDIR}/secrets"
  mkdir -p "${mock_bin}"

  # Create failing mock oci CLI
  cat <<'MOCK_EOF' > "${mock_bin}/oci"
#!/usr/bin/env bash
echo "Service unavailable" >&2
exit 1
MOCK_EOF
  chmod +x "${mock_bin}/oci"

  prepend_path "${mock_bin}"

  run bash "${SCRIPT_PATH}" --dest "${target_dir}" --vault-id "ocid1.vault.oc1..mock" restic_password
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Failed to fetch secret 'restic_password'"
  [ ! -f "${target_dir}/restic_password" ]
}
