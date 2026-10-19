#!/usr/bin/env bats
# Tests for .github/workflows/backup-dr-copy.yml (REV2-P2-5 / R2-OPS-02, OD-4)

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW_FILE="$REPO_ROOT/.github/workflows/backup-dr-copy.yml"
}

@test "backup-dr-copy.yml exists and is valid YAML" {
  [ -f "${WORKFLOW_FILE}" ]
  run yq eval '.' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
}

@test "backup-dr-copy.yml triggers on daily schedule (after 03:00 UTC + 30m jitter) and workflow_dispatch with boolean init input" {
  run yq eval '.on.schedule[0].cron' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "30 4 * * *" ]

  run yq eval '.on.workflow_dispatch.inputs.init.type' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "boolean" ]

  run yq eval '.on.workflow_dispatch.inputs.init.default' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "false" ]
}

@test "backup-dr-copy.yml sets top-level permissions: {} and dr-copy job runs on ubuntu-26.04 in ops environment" {
  run yq eval '.permissions | keys | length' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  run yq eval '.jobs.dr-copy.runs-on' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ubuntu-26.04" ]

  run yq eval '.jobs.dr-copy.environment' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ops" ]

  run yq eval '.jobs.dr-copy.permissions.contents' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "read" ]

  run yq eval '.jobs.dr-copy.timeout-minutes' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "45" ]

  run yq eval '.concurrency.cancel-in-progress' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "false" ]
}

@test "backup-dr-copy.yml uses Harden Runner with egress-policy: audit and setup-environment composite action" {
  run grep -E "step-security/harden-runner@[0-9a-f]{40}" "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]

  run grep -F "egress-policy: audit" "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]

  run grep -F "uses: $/.github/actions/setup-environment" "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
}

@test "backup-dr-copy.yml passes secrets and inputs via env: without expression interpolation inside run: blocks" {
  run yq eval '[.jobs[].steps[].run | select(. != null) | select(test("[$][{][{]"))] | length' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  local step_env
  step_env="$(yq eval '.jobs.dr-copy.steps[] | select(.name == "Copy Latest Primary Snapshots to Cloudflare R2 DR") | .env | keys | .[]' "${WORKFLOW_FILE}")"
  for key in INIT_REPOS OCI_BACKUP_HOSTS GCP_BACKUP_HOSTS \
             OCI_ENDPOINT OCI_BUCKET OCI_ACCESS_KEY OCI_SECRET_KEY OCI_PASS \
             GCP_ENDPOINT GCP_BUCKET GCP_ACCESS_KEY GCP_SECRET_KEY GCP_PASS \
             R2_ENDPOINT R2_BUCKET R2_ACCESS_KEY R2_SECRET_KEY R2_PASS; do
    echo "${step_env}" | grep -qx "${key}"
  done
}

@test "backup-dr-copy.yml copies latest snapshot from OCI and GCP primary buckets into R2 dr/<host> and supports init --copy-chunker-params" {
  local copy_run
  copy_run="$(yq eval '.jobs.dr-copy.steps[] | select(.name == "Copy Latest Primary Snapshots to Cloudflare R2 DR") | .run' "${WORKFLOW_FILE}")"

  echo "${copy_run}" | grep -qF 's3:${R2_ENDPOINT}/${R2_BUCKET}/dr/${host}'
  echo "${copy_run}" | grep -qF 's3:${OCI_ENDPOINT}/${OCI_BUCKET}/${host}'
  echo "${copy_run}" | grep -qF 's3:${GCP_ENDPOINT}/${GCP_BUCKET}/${host}'
  echo "${copy_run}" | grep -qF 'init --from-repo "${src_repo}" --copy-chunker-params'
  echo "${copy_run}" | grep -qF 'copy --from-repo "${src_repo}" latest'
}

@test "backup-dr-copy.yml reports Healthchecks.io heartbeat with always(), masks ping URL, and fails closed when unset" {
  run yq eval '.jobs.dr-copy.steps[] | select(.name == "Report DR Copy Heartbeat") | .if' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "always()" ]

  run yq eval '.jobs.dr-copy.steps[] | select(.name == "Report DR Copy Heartbeat") | .env.PING_URL' "${WORKFLOW_FILE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "HEALTHCHECKS_DR_COPY_PING_URL" ]] || false

  local hb_run
  hb_run="$(yq eval '.jobs.dr-copy.steps[] | select(.name == "Report DR Copy Heartbeat") | .run' "${WORKFLOW_FILE}")"
  echo "${hb_run}" | grep -qF 'echo "::add-mask::${PING_URL}"'
  echo "${hb_run}" | grep -qF '::error::HEALTHCHECKS_DR_COPY_PING_URL secret is not configured'
  echo "${hb_run}" | grep -qF '${PING_URL}/fail'
}
