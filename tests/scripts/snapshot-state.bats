#!/usr/bin/env bats
# Unit tests for scripts/snapshot-state.sh (REV2-P2-8) using stubbed aws/sops binaries.

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/snapshot-state.sh"

setup() {
  setup_tmpdir
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  BUCKET_DIR="${BATS_TEST_TMPDIR}/r2_bucket"
  mkdir -p "${STUB_BIN}" "${BUCKET_DIR}"

  cat >"${STUB_BIN}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Parse: aws s3 cp --endpoint-url <url> --only-show-errors <src> <dst>
src=""
dst=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    s3|cp|--only-show-errors)
      shift
      ;;
    --endpoint-url)
      shift 2
      ;;
    *)
      if [[ -z "${src}" ]]; then
        src="$1"
      else
        dst="$1"
      fi
      shift
      ;;
  esac
done

resolve_s3() {
  local uri="$1"
  local rel="${uri#s3://}"
  echo "${STUB_BUCKET_DIR}/${rel}"
}

if [[ "${src}" == s3://* ]]; then
  src_path="$(resolve_s3 "${src}")"
  [[ -f "${src_path}" ]] || exit 1
  mkdir -p "$(dirname "${dst}")"
  cp "${src_path}" "${dst}"
elif [[ "${dst}" == s3://* ]]; then
  dst_path="$(resolve_s3 "${dst}")"
  mkdir -p "$(dirname "${dst_path}")"
  if [[ "${STUB_CORRUPT_UPLOAD:-0}" -eq 1 ]]; then
    echo "corrupted-state-bytes" > "${dst_path}"
  else
    cp "${src}" "${dst_path}"
  fi
fi
EOF
  chmod +x "${STUB_BIN}/aws"
  export PATH="${STUB_BIN}:${PATH}"
  export STUB_BUCKET_DIR="${BUCKET_DIR}"
}

teardown() {
  teardown_tmpdir
}

@test "scripts/snapshot-state.sh is executable and supports --help" {
  [ -x "${SCRIPT}" ]
  run "${SCRIPT}" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: scripts/snapshot-state.sh"* ]]
}

@test "scripts/snapshot-state.sh rejects unknown module names" {
  AWS_ACCESS_KEY_ID="test-id" \
  AWS_SECRET_ACCESS_KEY="test-secret" \
  R2_ENDPOINT="https://r2.example.com" \
    run "${SCRIPT}" invalid-module
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown module"* ]]
}

@test "scripts/snapshot-state.sh fails closed when R2 credentials are missing" {
  SOPS_SECRETS_FILE="${BATS_TEST_TMPDIR}/nonexistent.sops.yaml" \
  AWS_ACCESS_KEY_ID="" \
  AWS_SECRET_ACCESS_KEY="" \
  R2_ENDPOINT="" \
    run "${SCRIPT}" oci
  [ "$status" -ne 0 ]
  [[ "$output" == *"R2 credentials"* ]]
}

@test "scripts/snapshot-state.sh snapshots a single module and verifies SHA-256 round-trip" {
  local state_dir="${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/state/oci"
  mkdir -p "${state_dir}"
  echo '{"encrypted":"state-payload-oci"}' > "${state_dir}/tofu.tfstate"

  AWS_ACCESS_KEY_ID="test-id" \
  AWS_SECRET_ACCESS_KEY="test-secret" \
  R2_ENDPOINT="https://r2.example.com" \
  SNAPSHOT_TIMESTAMP="20261015T120000Z" \
    run "${SCRIPT}" oci
  [ "$status" -eq 0 ]
  [ "$output" = "homelab-infra/snapshots/oci/20261015T120000Z.tfstate" ]
  [ -f "${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/snapshots/oci/20261015T120000Z.tfstate" ]
  cmp -s "${state_dir}/tofu.tfstate" "${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/snapshots/oci/20261015T120000Z.tfstate"
}

@test "scripts/snapshot-state.sh --all snapshots all 9 OpenTofu modules" {
  for mod in cloudflare dns oci gcp azure homelab github monitoring mesh; do
    mkdir -p "${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/state/${mod}"
    echo "{\"module\":\"${mod}\"}" > "${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/state/${mod}/tofu.tfstate"
  done

  AWS_ACCESS_KEY_ID="test-id" \
  AWS_SECRET_ACCESS_KEY="test-secret" \
  R2_ENDPOINT="https://r2.example.com" \
  SNAPSHOT_TIMESTAMP="20261015T120000Z" \
    run "${SCRIPT}" --all
  [ "$status" -eq 0 ]

  for mod in cloudflare dns oci gcp azure homelab github monitoring mesh; do
    [ -f "${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/snapshots/${mod}/20261015T120000Z.tfstate" ]
  done
}

@test "scripts/snapshot-state.sh fails closed when round-trip SHA-256 verification fails" {
  local state_dir="${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/state/gcp"
  mkdir -p "${state_dir}"
  echo '{"encrypted":"state-payload-gcp"}' > "${state_dir}/tofu.tfstate"

  STUB_CORRUPT_UPLOAD=1 \
  AWS_ACCESS_KEY_ID="test-id" \
  AWS_SECRET_ACCESS_KEY="test-secret" \
  R2_ENDPOINT="https://r2.example.com" \
  SNAPSHOT_TIMESTAMP="20261015T120000Z" \
    run "${SCRIPT}" gcp
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA-256 mismatch"* ]]
}

@test "scripts/snapshot-state.sh auto-derives R2 credentials and endpoint from SOPS JSON" {
  local state_dir="${BUCKET_DIR}/homelab-infra-tfstate/homelab-infra/state/monitoring"
  mkdir -p "${state_dir}"
  echo '{"encrypted":"state-payload-monitoring"}' > "${state_dir}/tofu.tfstate"

  local fake_sops="${BATS_TEST_TMPDIR}/fake.sops.yaml"
  : > "${fake_sops}"
  cat > "${STUB_BIN}/sops" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "opentofu": {
    "cloudflare_r2_access_key_id": "sops-r2-id",
    "cloudflare_r2_secret_access_key": "sops-r2-secret"
  },
  "cloudflare": {
    "config": {
      "account_id": "00000000000000000000000000000000"
    }
  }
}
JSON
EOF
  chmod +x "${STUB_BIN}/sops"

  SOPS_SECRETS_FILE="${fake_sops}" \
  AWS_ACCESS_KEY_ID="" \
  AWS_SECRET_ACCESS_KEY="" \
  R2_ENDPOINT="" \
  SNAPSHOT_TIMESTAMP="20261016T080000Z" \
    run "${SCRIPT}" monitoring
  [ "$status" -eq 0 ]
  [ "$output" = "homelab-infra/snapshots/monitoring/20261016T080000Z.tfstate" ]
}
