#!/usr/bin/env bats
# Tests for scripts/run-oxfmt.sh

load 'helpers/test_helper'

RUN_OXFMT_SCRIPT="${SCRIPTS_DIR}/run-oxfmt.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "run-oxfmt.sh skips files starting with GITCRYPT header" {
  local encrypted_file="${BATS_TMPDIR}/secret.md"
  printf '\0GITCRYPT\0fake_ciphertext_data' > "${encrypted_file}"

  run bash "${RUN_OXFMT_SCRIPT}" "${encrypted_file}"
  [ "$status" -eq 0 ]
  # Check that content was untouched
  local content
  content=$(cat "${encrypted_file}")
  [[ "$content" == *$'\0GITCRYPT\0fake_ciphertext_data'* ]]
}

@test "run-oxfmt.sh formats normal markdown files" {
  local normal_file="${BATS_TMPDIR}/normal.md"
  echo -e "# Hello World   \n\nSome text with trailing space   " > "${normal_file}"

  run bash "${RUN_OXFMT_SCRIPT}" "${normal_file}"
  [ "$status" -eq 0 ]
}

@test "run-oxfmt.sh formats unencrypted files while skipping encrypted files in mixed list" {
  local encrypted_file="${BATS_TMPDIR}/secret.md"
  local normal_file="${BATS_TMPDIR}/normal.md"
  printf '\0GITCRYPT\0fake_ciphertext_data' > "${encrypted_file}"
  echo "# Valid Heading" > "${normal_file}"

  run bash "${RUN_OXFMT_SCRIPT}" "${encrypted_file}" "${normal_file}"
  [ "$status" -eq 0 ]
}

@test "run-oxfmt.sh exits cleanly when no files are passed" {
  run bash "${RUN_OXFMT_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "run-oxfmt.sh exits cleanly when non-existent files are passed" {
  run bash "${RUN_OXFMT_SCRIPT}" "${BATS_TMPDIR}/nonexistent.md"
  [ "$status" -eq 0 ]
}
