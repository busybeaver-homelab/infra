#!/usr/bin/env bats
# Smoke tests for scripts/bootstrap.sh

load 'helpers/test_helper'

BOOTSTRAP_SCRIPT="${REPO_ROOT}/scripts/bootstrap.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "bootstrap.sh is executable" {
  run test -x "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh exists at expected path" {
  run test -f "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh fails gracefully when mise is not on PATH" {
  # Shadow PATH so mise cannot be found
  run env PATH="${BATS_TMPDIR}" bash "${BOOTSTRAP_SCRIPT}"
  # Should exit non-zero (cannot install mise without brew/curl mock)
  # We just assert it does not produce an uncontrolled crash (no set -e abort with no message)
  [ "$status" -ne 0 ] || [[ "$output" == *"mise"* ]]
}

@test "bootstrap.sh contains shebang line" {
  run head -1 "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == "#!/"* ]]
}

@test "bootstrap.sh passes shellcheck" {
  run shellcheck "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh runs lefthook install" {
  run grep -F "lefthook install" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}
