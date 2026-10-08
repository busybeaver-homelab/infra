#!/usr/bin/env bats
# Tests for scripts/bootstrap-state-backend.sh (Pattern A State Bootstrap)

load 'helpers/test_helper'

SCRIPT="${SCRIPTS_DIR}/bootstrap-state-backend.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "bootstrap-state-backend.sh exists and is executable" {
  run test -f "${SCRIPT}"
  [ "$status" -eq 0 ]
  run test -x "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap-state-backend.sh contains valid bash shebang" {
  run head -n 1 "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^#!/usr/bin/env\ bash ]]
}

@test "bootstrap-state-backend.sh passes shellcheck" {
  run shellcheck "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap-state-backend.sh passes shfmt check" {
  run shfmt -d -i 2 -ci "${SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap-state-backend.sh displays usage on --help and -h" {
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "Pattern A Workflow:" ]]
  [[ "$output" =~ "Stage 1:" ]]
  [[ "$output" =~ "Stage 2:" ]]
  [[ "$output" =~ "CLOUDFLARE_API_TOKEN" ]]
  [[ "$output" =~ "AWS_ACCESS_KEY_ID" ]]

  run "${SCRIPT}" -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "bootstrap-state-backend.sh fails on invalid option" {
  run "${SCRIPT}" --invalid-flag
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Unknown option: --invalid-flag" ]]
}

@test "bootstrap-state-backend.sh fails on invalid stage" {
  run "${SCRIPT}" --stage 3
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid stage '3'" ]]
}

@test "bootstrap-state-backend.sh fails on nonexistent module directory" {
  run "${SCRIPT}" --module-dir "${BATS_TMPDIR}/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Module directory does not exist" ]]
}

@test "bootstrap-state-backend.sh fails when required credentials are missing in non-dry-run mode" {
  # Run in clean subshell with credentials unset
  run env -i PATH="${PATH}" HOME="${HOME}" "${SCRIPT}" --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing required environment variable" ]]
}

@test "bootstrap-state-backend.sh succeeds in --dry-run mode even without credentials" {
  run env -i PATH="${PATH}" HOME="${HOME}" "${SCRIPT}" --dry-run --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY-RUN MODE" ]]
  [[ "$output" =~ "Stage 1: Local state bootstrap" ]]
  [[ "$output" =~ "Stage 2: Migrating state to Cloudflare R2" ]]
}

@test "bootstrap-state-backend.sh dry-run respects --stage 1 filter" {
  run "${SCRIPT}" --dry-run --stage 1 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Stage 1: Local state bootstrap" ]]
  [[ ! "$output" =~ "Stage 2: Migrating state" ]]
}

@test "bootstrap-state-backend.sh dry-run respects --stage 2 filter" {
  run "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Stage 1: Local state bootstrap" ]]
  [[ "$output" =~ "Stage 2: Migrating state" ]]
}

@test "bootstrap-state-backend.sh dry-run includes -auto-approve when --auto-approve or -y is passed" {
  run "${SCRIPT}" --dry-run --auto-approve --stage 1 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-auto-approve" ]]
}

@test "bootstrap-state-backend.sh dry-run uses custom bucket name when --bucket is passed" {
  run "${SCRIPT}" --dry-run --bucket "custom-tfstate-bucket" --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bucket=custom-tfstate-bucket" ]]
}

@test "bootstrap-state-backend.sh completes end-to-end two-stage workflow with mock tofu" {
  local mock_module_dir="${BATS_TMPDIR}/mock-cloudflare"
  mkdir -p "${mock_module_dir}"

  # Create mock backend.tf
  cat <<'EOF' > "${mock_module_dir}/backend.tf"
terraform {
  backend "s3" {
    endpoint = "https://<account_id>.eu.r2.cloudflarestorage.com"
    bucket   = "homelab-infra-tfstate"
  }
}
EOF

  # Create mock tofu binary that tracks invocations and simulates state generation
  local mock_bin_dir="${BATS_TMPDIR}/bin"
  mkdir -p "${mock_bin_dir}"
  local call_log="${BATS_TMPDIR}/tofu_calls.log"

  cat <<EOF > "${mock_bin_dir}/tofu"
#!/usr/bin/env bash
echo "\$*" >> "${call_log}"
# If running apply, create mock state file
for arg in "\$@"; do
  if [ "\$arg" = "apply" ]; then
    touch "${mock_module_dir}/terraform.tfstate"
  fi
done
exit 0
EOF
  chmod +x "${mock_bin_dir}/tofu"

  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_API_TOKEN="mock-cf-token" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    CLOUDFLARE_ZONE_ID="fedcba0987654321fedcba0987654321" \
    AWS_ACCESS_KEY_ID="mock-r2-access-key" \
    AWS_SECRET_ACCESS_KEY="mock-r2-secret-key" \
    "${SCRIPT}" --module-dir "${mock_module_dir}" --auto-approve

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Pattern A state backend bootstrap process completed successfully!" ]]

  # Verify backend.tf exists and is not left disabled
  [ -f "${mock_module_dir}/backend.tf" ]
  [ ! -f "${mock_module_dir}/backend.tf.disabled" ]

  # Verify local state was removed after migration
  [ ! -f "${mock_module_dir}/terraform.tfstate" ]

  # Verify tofu call sequence from log
  run cat "${call_log}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "init -input=false" ]]
  [[ "$output" =~ "apply -target=cloudflare_r2_bucket.tfstate -input=false -auto-approve" ]]
  [[ "$output" =~ "init -migrate-state -force-copy -input=false -backend-config=endpoint=https://1234567890abcdef1234567890abcdef.eu.r2.cloudflarestorage.com -backend-config=bucket=homelab-infra-tfstate" ]]
}

@test "bootstrap-state-backend.sh restores backend.tf on error during Stage 1 apply" {
  local mock_module_dir="${BATS_TMPDIR}/mock-cloudflare-fail"
  mkdir -p "${mock_module_dir}"

  cat <<'EOF' > "${mock_module_dir}/backend.tf"
terraform {
  backend "s3" {}
}
EOF

  local mock_bin_dir="${BATS_TMPDIR}/bin-fail"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' > "${mock_bin_dir}/tofu"
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "apply" ]; then
    echo "Simulated apply failure!" >&2
    exit 2
  fi
done
exit 0
EOF
  chmod +x "${mock_bin_dir}/tofu"

  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_API_TOKEN="mock-cf-token" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    CLOUDFLARE_ZONE_ID="fedcba0987654321fedcba0987654321" \
    AWS_ACCESS_KEY_ID="mock-r2-access-key" \
    AWS_SECRET_ACCESS_KEY="mock-r2-secret-key" \
    "${SCRIPT}" --module-dir "${mock_module_dir}" --auto-approve

  [ "$status" -ne 0 ]

  # Verify backend.tf was restored by trap
  [ -f "${mock_module_dir}/backend.tf" ]
  [ ! -f "${mock_module_dir}/backend.tf.disabled" ]
}
