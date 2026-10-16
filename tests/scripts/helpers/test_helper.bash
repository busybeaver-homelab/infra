#!/usr/bin/env bash
# Shared setup helpers for Bats test suites.

bats_require_minimum_version 1.5.0
if ((BASH_VERSINFO[0] < 4)); then
  echo "ERROR: Bash 4+ required (found ${BASH_VERSION}). Run via 'mise exec -- bats'." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export SCRIPTS_DIR="${REPO_ROOT}/scripts"

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

# Checks if a file is encrypted by git-crypt (starts with 10-byte \0GITCRYPT\0 header)
is_git_crypt_encrypted() {
  local target_file="${1}"
  head -c 10 "${target_file}" 2>/dev/null | grep -q "GITCRYPT"
}
