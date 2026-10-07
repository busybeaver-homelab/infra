#!/usr/bin/env bats
# Tests for scripts/check-network-masking.sh

load 'helpers/test_helper'

MASK_SCRIPT="${REPO_ROOT}/scripts/check-network-masking.sh"

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "check-network-masking.sh passes on clean files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'variable "project" { default = "homelab" }' > main.tf
  git add main.tf

  run bash "${MASK_SCRIPT}" "main.tf"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh exempts script itself and its tests" {
  run bash "${MASK_SCRIPT}" "scripts/check-network-masking.sh"
  [ "$status" -eq 0 ]

  run bash "${MASK_SCRIPT}" "tests/scripts/check-network-masking.bats"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh rejects staged RFC1918 10.0.0.0/8 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'cidr = "10.0.0.0/16"' > variables.tf
  git add variables.tf

  run bash "${MASK_SCRIPT}" "variables.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged RFC1918 172.16.0.0/12 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'subnet = "172.20.0.0/24"' > network.tf
  git add network.tf

  run bash "${MASK_SCRIPT}" "network.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged RFC1918 192.168.0.0/16 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'gateway: 192.168.1.1' > host_vars.yml
  git add host_vars.yml

  run bash "${MASK_SCRIPT}" "host_vars.yml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged Tailscale / CGNAT 100.64.0.0/10 literal" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'ip: "100.64.1.5"' > host.yml
  git add host.yml

  run bash "${MASK_SCRIPT}" "host.yml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh allows network patterns in *.sops.* files" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo 'subnet: 192.168.1.0/24' > secrets.sops.yaml
  git add secrets.sops.yaml

  run bash "${MASK_SCRIPT}" "secrets.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh allows network patterns in tests/fixtures/" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/tests/fixtures"
  cd "${mock_repo}"
  git init -q
  echo 'ip = "10.0.0.1"' > tests/fixtures/state.json
  git add tests/fixtures/state.json

  run bash "${MASK_SCRIPT}" "tests/fixtures/state.json"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh allows network patterns in docs/plans/" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/docs/plans"
  cd "${mock_repo}"
  git init -q
  echo 'Example: 10.0.0.0/16' > docs/plans/design.md
  git add docs/plans/design.md

  run bash "${MASK_SCRIPT}" "docs/plans/design.md"
  [ "$status" -eq 0 ]
}
