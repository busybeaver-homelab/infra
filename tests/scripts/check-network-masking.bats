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

@test "check-network-masking.sh passes on all tracked files in .agent/ and .agents/ (R2-GOV-04)" {
  cd "${REPO_ROOT}"
  run bash "${MASK_SCRIPT}" .agent .agents
  [ "$status" -eq 0 ]
}

@test "check-network-masking.sh fails closed (exit 2) on broken GIT_DIR" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"

  GIT_DIR="${BATS_TMPDIR}/nonexistent-git-dir" run bash "${MASK_SCRIPT}"
  [ "$status" -eq 2 ]
}

@test "check-network-masking.sh rejects non-RFC internal/tailnet hostnames (.ts.net, .internal, .lan, .home.arpa) and redacts output (R2-TF-10)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  local h_ts="node-alpha.tail99"".ts.net"
  local h_int="pve-core.corp"".internal"
  local h_lan="switch-01.office"".lan"
  local h_arpa="nas-box.local"".home.arpa"
  local ip_secret="10"".99.88.77"
  cat > hosts.tf <<EOF
ts = "${h_ts}"
int = "${h_int}"
lan = "${h_lan}"
arpa = "${h_arpa}"
ip = "${ip_secret}"
EOF
  git add hosts.tf

  run bash "${MASK_SCRIPT}" "hosts.tf"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Network masking violation" ]] || false
  [[ "$output" =~ "<redacted>.ts.net" ]] || false
  [[ "$output" =~ "<redacted>.internal" ]] || false
  [[ "$output" =~ "<redacted>.lan" ]] || false
  [[ "$output" =~ "<redacted>.home.arpa" ]] || false
  [[ "$output" =~ "10.x.x.x" ]] || false
  ! [[ "$output" =~ "node-alpha" ]] || false
  ! [[ "$output" =~ "pve-core" ]] || false
  ! [[ "$output" =~ "switch-01" ]] || false
  ! [[ "$output" =~ "nas-box" ]] || false
  ! [[ "$output" =~ "99.88.77" ]] || false
}

@test "check-network-masking.sh allows RFC 2606/6761 reserved test hostnames (*.example.*, *.test.*, *.invalid.*, *.localhost.*) (R2-TF-10)" {
  local mock_repo="${BATS_TMPDIR}/mock-repo"
  mkdir -p "${mock_repo}"
  cd "${mock_repo}"
  git init -q
  cat > test_fixtures.tf <<'EOF'
ts_host = "oci-amd-1.example.ts.net"
int_host = "proxmox.example.internal"
lan_host = "router.test.lan"
arpa_host = "gateway.localhost.home.arpa"
invalid_host = "node.invalid.ts.net"
EOF
  git add test_fixtures.tf

  run bash "${MASK_SCRIPT}" "test_fixtures.tf"
  [ "$status" -eq 0 ]
}
