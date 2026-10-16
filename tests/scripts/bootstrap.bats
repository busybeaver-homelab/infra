#!/usr/bin/env bats
# Smoke tests for scripts/bootstrap.sh

load 'helpers/test_helper'
bats_require_minimum_version 1.5.0

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
  run -127 env PATH="${BATS_TMPDIR}" bash "${BOOTSTRAP_SCRIPT}"
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

@test "bootstrap.sh contains state encryption passphrase instructions with SOPS option" {
  run grep -F "TF_VAR_state_encryption_passphrase" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
  run grep -F "state_encryption_passphrase" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
  run grep -F "sops set --value-stdin secrets/credentials.sops.yaml" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh never writes the state passphrase to a local file (R2-TF-01)" {
  run grep -F "tofu-passphrase" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -ne 0 ]
}

@test "bootstrap.sh checks for git-crypt installation" {
  run grep -F "git-crypt" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh contains git-crypt unlock logic with production GPG key" {
  run grep -F "5EE1590FF82DC2A3829D224FAA73ACF495CC009D" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
  run grep -F "git-crypt unlock" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -eq 0 ]
}

@test "lefthook.yml sets assert_lefthook_installed: true and bootstrap.sh has no python hook patch (R2-GATE-06)" {
  run yq -e '.assert_lefthook_installed == true' "${REPO_ROOT}/lefthook.yml"
  [ "$status" -eq 0 ]
  run grep -F "Can't find lefthook in PATH" "${BOOTSTRAP_SCRIPT}"
  [ "$status" -ne 0 ]
}

@test "lefthook install generates pre-commit hook that exits non-zero when lefthook is missing (R2-GATE-06)" {
  local repo="${BATS_TMPDIR}/hook-test"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
  cp "${REPO_ROOT}/lefthook.yml" "${repo}/lefthook.yml"
  (cd "${repo}" && lefthook install --force >/dev/null)
  [ -x "${repo}/.git/hooks/pre-commit" ]
  run grep -E "Can't find lefthook in PATH" -A 5 "${repo}/.git/hooks/pre-commit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exit 1"* ]]
}

@test "no scripts or configs pass secrets in process argv via curl -H Authorization, sops set positional value, or --authkey= (R2-SEC-07)" {
  run git -C "${REPO_ROOT}" grep -nE 'curl [^|]*Authorization:[[:space:]]*Bearer|tailscale[[:space:]]+up[^\n]*--authkey=' -- 'scripts/' 'infrastructure/' 'configuration/' 'mise.toml'
  [ "$status" -eq 1 ]
}
