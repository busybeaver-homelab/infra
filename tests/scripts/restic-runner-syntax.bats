#!/usr/bin/env bats
# Tests for configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2

load 'helpers/test_helper'

RUNNER_TEMPLATE="${REPO_ROOT}/configuration/roles/restic_backup/templates/restic-backup-runner.sh.j2"

@test "restic runner isolates targets by sourcing environment files inside subshells" {
  run grep -F '. "${env_file}"' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner auto-initializes repository via cat config and init with --retry-lock 2h" {
  run grep -F "restic --retry-lock 2h cat config" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
  run grep -F "restic --retry-lock 2h init" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner executes backup with retry-lock and target labels" {
  run grep -F "restic --retry-lock 2h backup" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
  run grep -E '\-\-tag[[:space:]]+"\$\{label\}"' "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner traps EXIT to guarantee post-backup hooks execution" {
  run grep -F "trap run_post_hooks EXIT" "${RUNNER_TEMPLATE}"
  [ "$status" -eq 0 ]
}

@test "restic runner tracks target failures and exits with error if any fail" {
  run grep -F 'FAILED_TARGETS' "${RUNNER_TEMPLATE}"
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

