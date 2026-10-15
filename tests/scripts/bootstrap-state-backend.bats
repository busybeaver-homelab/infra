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
  [[ "$output" =~ "Usage:" ]] || false
  [[ "$output" =~ "Pattern A Workflow:" ]] || false
  [[ "$output" =~ "Stage 1:" ]] || false
  [[ "$output" =~ "Stage 2:" ]] || false
  [[ "$output" =~ "TF_VAR_state_encryption_passphrase" ]] || false
  [[ "$output" =~ "CLOUDFLARE_API_TOKEN" ]] || false
  [[ "$output" =~ "AWS_ACCESS_KEY_ID" ]] || false

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
  [[ "$output" =~ "DRY-RUN MODE" ]] || false
  [[ "$output" =~ "Stage 1: Local state bootstrap" ]] || false
  [[ "$output" =~ "Stage 2: Migrating state to Cloudflare R2" ]]
}

@test "bootstrap-state-backend.sh dry-run respects --stage 1 filter" {
  run "${SCRIPT}" --dry-run --stage 1 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Stage 1: Local state bootstrap" ]] || false
  [[ ! "$output" =~ "Stage 2: Migrating state" ]]
}

@test "bootstrap-state-backend.sh dry-run respects --stage 2 filter" {
  run "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Stage 1: Local state bootstrap" ]] || false
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
  cat <<'EOF' >"${mock_module_dir}/backend.tf"
terraform {
  backend "s3" {
    endpoint = "https://<account_id>.r2.cloudflarestorage.com"
    bucket   = "homelab-infra-tfstate"
  }
}
EOF

  # Create mock tofu binary that tracks invocations and simulates state generation
  local mock_bin_dir="${BATS_TMPDIR}/bin"
  mkdir -p "${mock_bin_dir}"
  local call_log="${BATS_TMPDIR}/tofu_calls.log"

  cat <<EOF >"${mock_bin_dir}/tofu"
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
    TF_VAR_state_encryption_passphrase="mock-state-passphrase-32-chars-ok" \
    "${SCRIPT}" --module-dir "${mock_module_dir}" --auto-approve

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Pattern A state backend bootstrap process completed successfully!" ]] || false

  # Verify backend.tf exists and is not left disabled
  [ -f "${mock_module_dir}/backend.tf" ]
  [ ! -f "${mock_module_dir}/backend.tf.disabled" ]

  # Verify local state was removed after migration
  [ ! -f "${mock_module_dir}/terraform.tfstate" ]

  # Verify tofu call sequence from log
  run cat "${call_log}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "init -input=false" ]] || false
  [[ "$output" =~ "apply -target=cloudflare_r2_bucket.tfstate -input=false -auto-approve" ]] || false
  [[ "$output" =~ "init -migrate-state -force-copy -input=false -backend-config=endpoint=https://1234567890abcdef1234567890abcdef.r2.cloudflarestorage.com -backend-config=bucket=homelab-infra-tfstate" ]]
}

@test "bootstrap-state-backend.sh restores backend.tf on error during Stage 1 apply" {
  local mock_module_dir="${BATS_TMPDIR}/mock-cloudflare-fail"
  mkdir -p "${mock_module_dir}"

  cat <<'EOF' >"${mock_module_dir}/backend.tf"
terraform {
  backend "s3" {}
}
EOF

  local mock_bin_dir="${BATS_TMPDIR}/bin-fail"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/tofu"
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
    TF_VAR_state_encryption_passphrase="mock-state-passphrase-32-chars-ok" \
    "${SCRIPT}" --module-dir "${mock_module_dir}" --auto-approve

  [ "$status" -ne 0 ]

  # Verify backend.tf was restored by trap
  [ -f "${mock_module_dir}/backend.tf" ]
  [ ! -f "${mock_module_dir}/backend.tf.disabled" ]
}

@test "bootstrap-state-backend.sh auto-resolves AWS credentials from SOPS when unset" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
if [[ "$*" =~ --extract.*opentofu ]]; then
  echo 'cloudflare_r2_access_key_id: mock-auto-sops-key-id'
  echo 'cloudflare_r2_secret_access_key: mock-auto-sops-secret-key'
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    SOPS_SECRETS_FILE="${REPO_ROOT}/secrets/credentials.ci.sops.yaml" \
    "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Auto-resolved AWS_ACCESS_KEY_ID from SOPS" ]] || false
  [[ "$output" =~ "Auto-resolved AWS_SECRET_ACCESS_KEY from SOPS" ]]
}

@test "bootstrap-state-backend.sh preserves explicit AWS credentials over SOPS auto-resolution" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops-preserve"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
echo "sops should not be called" >&2
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    AWS_ACCESS_KEY_ID="explicit-key" \
    AWS_SECRET_ACCESS_KEY="explicit-secret" \
    "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Auto-resolved AWS_ACCESS_KEY_ID from SOPS" ]]
}

@test "bootstrap-state-backend.sh fails stage 2 when credentials are missing and cannot be resolved" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops-fail"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env -i \
    PATH="${mock_bin_dir}:${PATH}" \
    HOME="${HOME}" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    "${SCRIPT}" --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing required environment variable: AWS_ACCESS_KEY_ID" ]]
}

@test "bootstrap-state-backend.sh auto-resolves state encryption passphrase from SOPS when unset" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops-pass"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
if [[ "$*" =~ --extract.*opentofu ]]; then
  echo 'cloudflare_r2_access_key_id: mock-auto-sops-key-id'
  echo 'cloudflare_r2_secret_access_key: mock-auto-sops-secret-key'
  echo 'state_encryption_passphrase: mock-auto-sops-passphrase'
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    SOPS_SECRETS_FILE="${REPO_ROOT}/secrets/credentials.ci.sops.yaml" \
    "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Auto-resolved TF_VAR_state_encryption_passphrase from SOPS" ]]
}

@test "bootstrap-state-backend.sh preserves explicit TF_VAR_state_encryption_passphrase over SOPS auto-resolution" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops-pass-preserve"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
if [[ "$*" =~ --extract.*opentofu ]]; then
  echo 'cloudflare_r2_access_key_id: mock-auto-sops-key-id'
  echo 'cloudflare_r2_secret_access_key: mock-auto-sops-secret-key'
  echo 'state_encryption_passphrase: mock-auto-sops-passphrase'
  exit 0
fi
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    SOPS_SECRETS_FILE="${REPO_ROOT}/secrets/credentials.ci.sops.yaml" \
    TF_VAR_state_encryption_passphrase="explicit-user-passphrase" \
    "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Auto-resolved TF_VAR_state_encryption_passphrase from SOPS" ]]
}

@test "bootstrap-state-backend.sh ignores a local passphrase file and reports the missing passphrase" {
  local mock_home="${BATS_TMPDIR}/mock-home"
  mkdir -p "${mock_home}/.config/homelab-infra"
  echo "mock-local-file-passphrase" > "${mock_home}/.config/homelab-infra/tofu-passphrase"

  local mock_bin_dir="${BATS_TMPDIR}/bin-no-sops"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env -u TF_VAR_state_encryption_passphrase \
    HOME="${mock_home}" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    AWS_ACCESS_KEY_ID="mock-key" \
    AWS_SECRET_ACCESS_KEY="mock-secret" \
    "${SCRIPT}" --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ "$output" != *"from local file"* ]] || false
  [[ "$output" == *"Missing required environment variable: TF_VAR_state_encryption_passphrase"* ]]
}

@test "bootstrap-state-backend.sh fails without the state passphrase outside dry-run" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-no-sops-strict"
  mkdir -p "${mock_bin_dir}"
  printf '#!/usr/bin/env bash\nexit 1\n' >"${mock_bin_dir}/sops"
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env -u TF_VAR_state_encryption_passphrase \
    HOME="${BATS_TMPDIR}" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    AWS_ACCESS_KEY_ID="mock-key" \
    AWS_SECRET_ACCESS_KEY="mock-secret" \
    "${SCRIPT}" --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 1 ]
  [[ "$output" == *"TF_VAR_state_encryption_passphrase"* ]]
}

@test "bootstrap-state-backend.sh fails on invalid --env value" {
  run "${SCRIPT}" --env staging
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid environment 'staging'" ]]
}

@test "bootstrap-state-backend.sh --env prod fails when gpg is unavailable without reading credentials.ci.sops.yaml (R2-SEC-05)" {
  local no_gpg_bin="${BATS_TMPDIR}/no-gpg-bin"
  mkdir -p "${no_gpg_bin}"
  local sops_log="${BATS_TMPDIR}/sops_invocations.log"

  # Symlink required tools except gpg
  for tool in bash env dirname basename cd pwd cat printf tr sed sort rm mv head tofu yq; do
    if command -v "$tool" >/dev/null 2>&1; then
      ln -sf "$(command -v "$tool")" "${no_gpg_bin}/${tool}"
    fi
  done

  cat <<EOF >"${no_gpg_bin}/sops"
#!/usr/bin/env bash
echo "\$*" >> "${sops_log}"
exit 0
EOF
  chmod +x "${no_gpg_bin}/sops"

  run env -i \
    PATH="${no_gpg_bin}" \
    HOME="${BATS_TMPDIR}" \
    SOPS_AGE_KEY="AGE-SECRET-KEY-SYNTHETIC" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    "${SCRIPT}" --env prod --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "requires 'gpg' on PATH" ]] || false
  [ ! -f "${sops_log}" ]
}

@test "bootstrap-state-backend.sh --env ci explicitly reads secrets/credentials.ci.sops.yaml (R2-SEC-05)" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-env-ci"
  mkdir -p "${mock_bin_dir}"
  local sops_log="${BATS_TMPDIR}/sops_ci.log"

  cat <<EOF >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
echo "\$*" >> "${sops_log}"
echo 'cloudflare_r2_access_key_id: mock-ci-key-id'
echo 'cloudflare_r2_secret_access_key: mock-ci-secret-key'
echo 'state_encryption_passphrase: mock-ci-passphrase'
exit 0
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  run env -u SOPS_SECRETS_FILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u TF_VAR_state_encryption_passphrase \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    "${SCRIPT}" --env ci --dry-run --stage 2 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "credentials.ci.sops.yaml" ]] || false
  run cat "${sops_log}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "secrets/credentials.ci.sops.yaml" ]]
}

@test "bootstrap-state-backend.sh aborts when sops fails even if stage 1 variables are provided (R2-SEC-05)" {
  local mock_bin_dir="${BATS_TMPDIR}/bin-sops-abort"
  mkdir -p "${mock_bin_dir}"

  cat <<'EOF' >"${mock_bin_dir}/sops"
#!/usr/bin/env bash
echo "sops decryption failure: MAC mismatch" >&2
exit 1
EOF
  chmod +x "${mock_bin_dir}/sops"
  prepend_path "${mock_bin_dir}"

  # Stage 1 variables + passphrase are set, but AWS_ACCESS_KEY_ID is unset so resolve_sops_credentials runs
  run env -u AWS_ACCESS_KEY_ID \
    CLOUDFLARE_API_TOKEN="mock-cf-token" \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    CLOUDFLARE_ZONE_ID="fedcba0987654321fedcba0987654321" \
    TF_VAR_state_encryption_passphrase="mock-state-passphrase-32-chars-ok" \
    "${SCRIPT}" --env ci --stage 1 --module-dir "${REPO_ROOT}/infrastructure/cloudflare"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "sops decryption failure: MAC mismatch" ]] || false
  [[ "$output" =~ "Failed to decrypt SOPS credentials" ]]
}

@test "bootstrap-state-backend.sh verifies tofu state list matches local state before deleting terraform.tfstate (R2-SEC-05)" {
  local mock_module_dir="${BATS_TMPDIR}/mock-cloudflare-verify"
  mkdir -p "${mock_module_dir}"

  cat <<'EOF' >"${mock_module_dir}/backend.tf"
terraform {
  backend "s3" {}
}
EOF

  cat <<'EOF' >"${mock_module_dir}/terraform.tfstate"
{
  "version": 4,
  "resources": [
    {
      "mode": "managed",
      "type": "cloudflare_r2_bucket",
      "name": "tfstate",
      "instances": [{"schema_version": 0}]
    }
  ]
}
EOF

  local mock_bin_dir="${BATS_TMPDIR}/bin-verify"
  mkdir -p "${mock_bin_dir}"

  # First: simulate remote state list mismatch (empty remote state) -> must abort and preserve local terraform.tfstate
  cat <<'EOF' >"${mock_bin_dir}/tofu"
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${mock_bin_dir}/tofu"
  prepend_path "${mock_bin_dir}"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    AWS_ACCESS_KEY_ID="mock-r2-access-key" \
    AWS_SECRET_ACCESS_KEY="mock-r2-secret-key" \
    TF_VAR_state_encryption_passphrase="mock-state-passphrase-32-chars-ok" \
    "${SCRIPT}" --stage 2 --module-dir "${mock_module_dir}"

  [ "$status" -eq 1 ]
  [[ "$output" =~ "Remote state resource list does not match local terraform.tfstate" ]] || false
  [ -f "${mock_module_dir}/terraform.tfstate" ]

  # Second: simulate remote state list matching local state -> must succeed and delete local terraform.tfstate
  cat <<'EOF' >"${mock_bin_dir}/tofu"
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "list" ]; then
    echo "cloudflare_r2_bucket.tfstate"
  fi
done
exit 0
EOF
  chmod +x "${mock_bin_dir}/tofu"

  run env \
    CLOUDFLARE_ACCOUNT_ID="1234567890abcdef1234567890abcdef" \
    AWS_ACCESS_KEY_ID="mock-r2-access-key" \
    AWS_SECRET_ACCESS_KEY="mock-r2-secret-key" \
    TF_VAR_state_encryption_passphrase="mock-state-passphrase-32-chars-ok" \
    "${SCRIPT}" --stage 2 --module-dir "${mock_module_dir}"

  [ "$status" -eq 0 ]
  [ ! -f "${mock_module_dir}/terraform.tfstate" ]
}

