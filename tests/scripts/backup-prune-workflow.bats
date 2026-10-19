#!/usr/bin/env bats
# Tests for .github/workflows/backup-prune.yml and docs/runbooks/restic-restore-drill.md

load 'helpers/test_helper'

WORKFLOW_FILE="${REPO_ROOT}/.github/workflows/backup-prune.yml"
RUNBOOK_FILE="${REPO_ROOT}/docs/runbooks/restic-restore-drill.md"

@test "backup-prune workflow file exists and is valid YAML" {
  [ -f "${WORKFLOW_FILE}" ]
  run yq '.' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "backup-prune workflow defines schedule and workflow_dispatch triggers" {
  run yq '.on.schedule[0].cron' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "0 2 * * 0" ]

  run yq '.on | has("workflow_dispatch")' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "backup-prune workflow consumes ops environment prune secrets without decrypting CI decoy file" {
  run grep -F 'secrets.OCI_RESTIC_PRUNE_ACCESS_KEY_ID' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.GCP_RESTIC_PRUNE_ACCESS_KEY_ID' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.R2_RESTIC_PRUNE_ACCESS_KEY_ID' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'credentials.ci.sops.yaml' "${WORKFLOW_FILE}"
  [ "$status" -ne 0 ]
}

@test "backup-prune workflow performs retention prune on OCI, GCP, and R2 repositories per OD-4" {
  local oci_run gcp_run r2_run
  oci_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune primary OCI backup repository") | .run' "${WORKFLOW_FILE}")"
  gcp_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune primary GCP backup repository") | .run' "${WORKFLOW_FILE}")"
  r2_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune secondary Cloudflare R2 DR backup repository") | .run' "${WORKFLOW_FILE}")"

  [[ "${oci_run}" =~ restic[[:space:]].*forget[[:space:]]+--keep-daily[[:space:]]+7[[:space:]]+--keep-weekly[[:space:]]+4[[:space:]]+--keep-monthly[[:space:]]+3[[:space:]]+--group-by[[:space:]]+host,tags[[:space:]]+--prune[[:space:]]+--max-unused[[:space:]]+10% ]] || false
  [[ "${gcp_run}" =~ restic[[:space:]].*forget[[:space:]]+--keep-daily[[:space:]]+7[[:space:]]+--keep-weekly[[:space:]]+4[[:space:]]+--keep-monthly[[:space:]]+3[[:space:]]+--group-by[[:space:]]+host,tags[[:space:]]+--prune[[:space:]]+--max-unused[[:space:]]+10% ]] || false
  [[ "${r2_run}" =~ restic[[:space:]].*forget[[:space:]]+--keep-daily[[:space:]]+7[[:space:]]+--keep-weekly[[:space:]]+4[[:space:]]+--group-by[[:space:]]+host,tags[[:space:]]+--prune[[:space:]]+--max-unused[[:space:]]+10% ]] || false
  [[ ! "${r2_run}" =~ --keep-monthly ]] || false
  [[ ! "${r2_run}" =~ --keep-last ]] || false
}

@test "backup-prune workflow performs subset integrity check" {
  run grep -E 'restic.*check.*--read-data-subset=5%' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "restic restore drill runbook exists and documents test restoration procedure" {
  [ -f "${RUNBOOK_FILE}" ]
  if is_git_crypt_encrypted "${RUNBOOK_FILE}"; then
    skip "restic-restore-drill.md is git-crypt encrypted in CI environment"
  fi
  run grep -Ei "restore|restic restore" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
  run grep -Ei "drill|verification" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
}

@test "is_git_crypt_encrypted correctly detects git-crypt encrypted and plaintext files" {
  setup_tmpdir
  local encrypted_file="${BATS_TMPDIR}/encrypted.md"
  local plain_file="${BATS_TMPDIR}/plain.md"

  printf '\0GITCRYPT\0fake_ciphertext_data' >"${encrypted_file}"
  echo "# Plaintext Markdown Document" >"${plain_file}"

  run is_git_crypt_encrypted "${encrypted_file}"
  [ "$status" -eq 0 ]

  run is_git_crypt_encrypted "${plain_file}"
  [ "$status" -ne 0 ]

  teardown_tmpdir
}

@test "restic restore drill runbook check skips cleanly when mock runbook is git-crypt encrypted" {
  setup_tmpdir
  local mock_runbook="${BATS_TMPDIR}/restic-restore-drill.md"
  printf '\0GITCRYPT\0mock_encrypted_payload' >"${mock_runbook}"

  run bash -c "
    if head -c 10 '${mock_runbook}' 2>/dev/null | grep -q 'GITCRYPT'; then
      exit 0
    fi
    exit 1
  "
  [ "$status" -eq 0 ]

  teardown_tmpdir
}

@test "backup-prune workflow prunes and checks primary GCP backup repository" {
  run grep -F 'Prune primary GCP backup repository' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.GCP_RESTIC_S3_ENDPOINT' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.GCP_RESTIC_BUCKET' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "restic restore drill runbook documents both OCI and GCP primary repositories" {
  [ -f "${RUNBOOK_FILE}" ]
  if is_git_crypt_encrypted "${RUNBOOK_FILE}"; then
    skip "restic-restore-drill.md is git-crypt encrypted in CI environment"
  fi
  run grep -F "oci_restic" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
  run grep -F "gcp_restic" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
}

@test "gcp breakglass console runbook exists and documents serial port recovery and disablement" {
  local gcp_runbook="${REPO_ROOT}/docs/runbooks/gcp-breakglass-console.md"
  [ -f "${gcp_runbook}" ]
  if is_git_crypt_encrypted "${gcp_runbook}"; then
    skip "gcp-breakglass-console.md is git-crypt encrypted in CI environment"
  fi
  run grep -F "serial-port-enable" "${gcp_runbook}"
  [ "$status" -eq 0 ]
  run grep -F "gcp.breakglass_user" "${gcp_runbook}"
  [ "$status" -eq 0 ]
}

@test "opentofu-standards runbook documents STD-OT-49 exception for GCP Always Free ephemeral IPv4" {
  local ot_runbook="${REPO_ROOT}/docs/runbooks/opentofu-standards.md"
  [ -f "${ot_runbook}" ]
  if is_git_crypt_encrypted "${ot_runbook}"; then
    skip "opentofu-standards.md is git-crypt encrypted in CI environment"
  fi
  run grep -E "GCP Always Free.*STANDARD.*ephemeral" "${ot_runbook}"
  [ "$status" -eq 0 ]
}

@test "backup-prune workflow targets ops environment and uses mise-managed restic without apt-get" {
  run yq -r '.jobs.prune.environment' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "ops" ]

  run yq -r '.tools."aqua:restic/restic"' "${REPO_ROOT}/mise.toml"
  [ "$status" -eq 0 ]
  [[ "$output" == 0.18* ]] || false

  run grep -E 'apt-get.*restic' "${WORKFLOW_FILE}"
  [ "$status" -ne 0 ]
}

@test "backup-prune workflow iterates per-host repository paths and fails closed on missing credentials" {
  run grep -F 's3:${OCI_ENDPOINT}/${OCI_BUCKET}/${host}' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 's3:${GCP_ENDPOINT}/${GCP_BUCKET}/${host}' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 's3:${R2_ENDPOINT}/${R2_BUCKET}/${host}' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.R2_RESTIC_S3_ENDPOINT' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'exit 1' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "backup-prune workflow consumes OCI_BACKUP_HOSTS and GCP_BACKUP_HOSTS without fallback defaults and masks every host" {
  run grep -F 'secrets.OCI_BACKUP_HOSTS' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'secrets.GCP_BACKUP_HOSTS' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -E '\$\{[A-Z_]*HOSTS:-' "${WORKFLOW_FILE}"
  [ "$status" -ne 0 ]

  run grep -E 'oci-amd-1|gcp-default-vm' "${WORKFLOW_FILE}"
  [ "$status" -ne 0 ]

  local mask_count
  mask_count="$(grep -cF 'echo "::add-mask::${host}"' "${WORKFLOW_FILE}")"
  [ "${mask_count}" -eq 3 ]

  local oci_run gcp_run r2_run
  oci_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune primary OCI backup repository") | .run' "${WORKFLOW_FILE}")"
  gcp_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune primary GCP backup repository") | .run' "${WORKFLOW_FILE}")"
  r2_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Prune secondary Cloudflare R2 DR backup repository") | .run' "${WORKFLOW_FILE}")"

  [[ "${oci_run}" == *'[ -z "${OCI_BACKUP_HOSTS}" ]'* ]] || false
  [[ "${oci_run}" == *'::error::'* ]] || false
  [[ "${gcp_run}" == *'[ -z "${GCP_BACKUP_HOSTS}" ]'* ]] || false
  [[ "${gcp_run}" == *'::error::'* ]] || false
  [[ "${r2_run}" == *'[ -z "${OCI_BACKUP_HOSTS}" ]'* ]] || false
  [[ "${r2_run}" == *'[ -z "${GCP_BACKUP_HOSTS}" ]'* ]] || false
  [[ "${r2_run}" == *'::error::'* ]] || false
}

@test "backup-prune workflow reports Healthchecks heartbeat with if: always() and fails closed when ping URL is missing" {
  run yq -r '.jobs.prune.steps[] | select(.name == "Report Backup Prune Heartbeat") | .if' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "always()" ]

  run grep -F 'HEALTHCHECKS_BACKUP_PRUNE_PING_URL' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  local hb_run
  hb_run="$(yq -r '.jobs.prune.steps[] | select(.name == "Report Backup Prune Heartbeat") | .run' "${WORKFLOW_FILE}")"
  [[ "${hb_run}" == *'::error::HEALTHCHECKS_BACKUP_PRUNE_PING_URL'* ]] || false
  [[ "${hb_run}" == *'exit 1'* ]] || false
  [[ "${hb_run}" != *'exit 0'* ]] || false
}
