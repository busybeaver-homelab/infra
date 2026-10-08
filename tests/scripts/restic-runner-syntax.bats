#!/usr/bin/env bats
# Tests for configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2

load 'helpers/test_helper'

RUNNER_TEMPLATE="${REPO_ROOT}/configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2"

@test "restic runner does not contain source calls" {
  run grep -E "^[[:space:]]*(source|\.)[[:space:]]" "${RUNNER_TEMPLATE}"
  [ "$status" -ne 0 ]
}

@test "restic runner verifies repo via cat config with --retry-lock 2h" {
  run grep -F "restic --retry-lock 2h cat config" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner uses --retry-lock 2h for backup" {
  run grep -F "restic --retry-lock 2h backup" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner contains restic copy for secondary repository dual-sync" {
  run grep -F "restic --retry-lock 2h copy" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner does not perform forget prune on the host" {
  run grep -E "restic[[:space:]]+forget" "${RUNNER_TEMPLATE}"
  [ "$status" -ne 0 ]
}

@test "restic runner sends healthchecks heartbeat ping on success" {
  run grep -F 'curl -fsS -m 10 --retry 3 "${HEALTHCHECKS_PING_URL}"' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}
