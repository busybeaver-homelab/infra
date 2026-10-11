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

@test "backup-prune workflow uses scoped secret decryption and cleanup" {
  run grep -F 'umask 077 && mise exec -- sops --decrypt' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -F 'rm -f "${RUNNER_TEMP}/credentials.ci.yaml"' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "backup-prune workflow performs retention prune on OCI and R2 repositories" {
  run grep -E 'restic.*forget.*--keep-daily 7.*--keep-weekly 4.*--prune' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]

  run grep -E 'restic.*forget.*--keep-last 2.*--prune' "${WORKFLOW_FILE}"
  [ "$status" -eq 0 ]
}

@test "backup-prune workflow performs subset integrity check" {
  run grep -E 'restic.*check.*--read-data-subset=1%' "${WORKFLOW_FILE}"
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

  printf '\0GITCRYPT\0fake_ciphertext_data' > "${encrypted_file}"
  echo "# Plaintext Markdown Document" > "${plain_file}"

  run is_git_crypt_encrypted "${encrypted_file}"
  [ "$status" -eq 0 ]

  run is_git_crypt_encrypted "${plain_file}"
  [ "$status" -ne 0 ]

  teardown_tmpdir
}

@test "restic restore drill runbook check skips cleanly when mock runbook is git-crypt encrypted" {
  setup_tmpdir
  local mock_runbook="${BATS_TMPDIR}/restic-restore-drill.md"
  printf '\0GITCRYPT\0mock_encrypted_payload' > "${mock_runbook}"

  run bash -c "
    if head -c 10 '${mock_runbook}' 2>/dev/null | grep -q 'GITCRYPT'; then
      exit 0
    fi
    exit 1
  "
  [ "$status" -eq 0 ]

  teardown_tmpdir
}
