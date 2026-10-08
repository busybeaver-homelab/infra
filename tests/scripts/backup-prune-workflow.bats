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
  run grep -Ei "restore|restic restore" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
  run grep -Ei "drill|verification" "${RUNBOOK_FILE}"
  [ "$status" -eq 0 ]
}
