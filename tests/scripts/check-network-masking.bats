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

@test "check-network-masking.sh passes when scanning itself and its own Bats file without exemptions" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/scripts" "${mock_repo}/tests/scripts"
  cd "${mock_repo}"
  git init -q
  cp "${MASK_SCRIPT}" scripts/check-network-masking.sh
  cp "${REPO_ROOT}/tests/scripts/check-network-masking.bats" tests/scripts/check-network-masking.bats
  git add scripts/check-network-masking.sh tests/scripts/check-network-masking.bats

  run bash "${MASK_SCRIPT}" "scripts/check-network-masking.sh" "tests/scripts/check-network-masking.bats"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh rejects staged RFC1918 10.x.x.x/8 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.0/16"
  echo "cidr = \"${ip10}\"" > variables.tf
  git add variables.tf

  run bash "${MASK_SCRIPT}" "variables.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged RFC1918 172.16-31.x.x/12 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip172="172"".20.0.0/24"
  echo "subnet = \"${ip172}\"" > network.tf
  git add network.tf

  run bash "${MASK_SCRIPT}" "network.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged RFC1918 192.168.x.x/16 CIDR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip192="192.168"".1.1"
  echo "gateway: ${ip192}" > host_vars.yml
  git add host_vars.yml

  run bash "${MASK_SCRIPT}" "host_vars.yml"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged Tailscale / CGNAT 100.64-127.x.x/10 literal" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip100="100.64"".1.5"
  echo "ip: \"${ip100}\"" > host.yml
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
  local ip192="192.168"".1.0/24"
  echo "subnet: ${ip192}" > secrets.sops.yaml
  git add secrets.sops.yaml

  run bash "${MASK_SCRIPT}" "secrets.sops.yaml"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh rejects network patterns in tests/fixtures/ and .bats files (no test exemptions)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/tests/fixtures" "${mock_repo}/tests/scripts"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.1"
  echo "ip = \"${ip10}\"" > tests/fixtures/state.json
  echo "ip = \"${ip10}\"" > tests/scripts/check-network-masking.bats
  git add tests/fixtures/state.json tests/scripts/check-network-masking.bats

  run bash "${MASK_SCRIPT}" "tests/fixtures/state.json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]] || false

  run bash "${MASK_SCRIPT}" "tests/scripts/check-network-masking.bats"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh allows network patterns in docs/plans/" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/docs/plans"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.0/16"
  echo "Example: ${ip10}" > docs/plans/design.md
  git add docs/plans/design.md

  run bash "${MASK_SCRIPT}" "docs/plans/design.md"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh allows network patterns in backups/" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/backups"
  cd "${mock_repo}"
  git init -q
  local ip192="192.168"".1.1"
  echo "unifi_controller_ip: ${ip192}" > backups/unifi.json
  git add backups/unifi.json

  run bash "${MASK_SCRIPT}" "backups/unifi.json"
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh scans multiple files in batched mode efficiently" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  for i in $(seq 1 20); do
    echo "safe_var: sample_$i" > "file_$i.tf"
  done
  git add file_*.tf

  run bash "${MASK_SCRIPT}" file_*.tf
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh detects multiple network violations in batched mode" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.0/16"
  local ip192="192.168"".1.1"
  echo 'safe: "homelab"' > clean.tf
  echo "cidr = \"${ip10}\"" > leak1.tf
  echo "subnet = \"${ip192}\"" > leak2.tf
  git add clean.tf leak1.tf leak2.tf

  run bash "${MASK_SCRIPT}" clean.tf leak1.tf leak2.tf
  [ "$status" -ne 0 ]
  [[ "$output" =~ "leak1.tf" ]] || false
  [[ "$output" =~ "leak2.tf" ]] || false
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged IPv6 Unique Local Address (ULA fc00::/7)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip_ula="fd12"":3456:789a:1::1"
  echo "ipv6_ula = \"${ip_ula}\"" > network.tf
  git add network.tf

  run bash "${MASK_SCRIPT}" "network.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects port-bearing private IP literals" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip192="192.168"".1.100:8006"
  echo "proxmox_url = \"${ip192}\"" > endpoint.tf
  git add endpoint.tf

  run bash "${MASK_SCRIPT}" "endpoint.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects URLs with embedded private IPs" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.5"
  echo "api = \"https://${ip10}/api2/json\"" > api.tf
  git add api.tf

  run bash "${MASK_SCRIPT}" "api.tf"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged file containing NUL byte and RFC1918 IP" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".0.0.42"
  printf '\x00\ncidr = "%s"\n' "${ip10}" > binary-config.bin
  git add binary-config.bin

  run bash "${MASK_SCRIPT}" "binary-config.bin"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged file marked -diff in .gitattributes containing RFC1918 IP" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  echo "*.dat -diff" > .gitattributes
  local ip192="192.168"".10.50"
  echo "host_ip = ${ip192}" > inventory.dat
  git add .gitattributes inventory.dat

  run bash "${MASK_SCRIPT}" "inventory.dat"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh rejects staged file under .agent/ containing RFC1918 IP (R2-GOV-04)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}/.agent"
  cd "${mock_repo}"
  git init -q
  local ip10="10"".10.10.1"
  echo "Internal server IP: ${ip10}" > .agent/notes.md
  git add .agent/notes.md

  run bash "${MASK_SCRIPT}" ".agent/notes.md"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Network masking violation" ]]
}

@test "check-network-masking.sh fails closed (exit 2) on broken GIT_DIR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"

  GIT_DIR="${BATS_TMPDIR}/nonexistent-git-dir" run bash "${MASK_SCRIPT}"
  [ "$status" -eq 2 ]
}
