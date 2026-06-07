#!/usr/bin/env bash
# Shared setup helpers for Bats test suites.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# Adds a directory to the front of PATH for the duration of a test.
prepend_path() {
  export PATH="${1}:${PATH}"
}

# Creates a temporary directory and sets BATS_TMPDIR.
setup_tmpdir() {
  BATS_TMPDIR="$(mktemp -d)"
  export BATS_TMPDIR
}

# Removes the temporary directory created by setup_tmpdir.
teardown_tmpdir() {
  rm -rf "${BATS_TMPDIR}"
}
