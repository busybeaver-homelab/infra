#!/usr/bin/env bats
# Tests for dynamic Ansible inventory with OpenTofu state fixtures

load 'helpers/test_helper'

FIXTURE_SRC="${REPO_ROOT}/configuration/inventories/fixtures/oci_state.json"
TEST_INV="${REPO_ROOT}/configuration/inventories/test.terraform_state.yml"
TMP_STATE="/tmp/homelab_test_oci_state.json"

setup() {
  setup_tmpdir
  cp "${FIXTURE_SRC}" "${TMP_STATE}"
}

teardown() {
  rm -f "${TMP_STATE}"
  teardown_tmpdir
}

@test "dynamic inventory parses test state fixture and outputs expected hosts and groups" {
  run ansible-inventory -i "${TEST_INV}" --graph
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oci-amd-1" ]]
  [[ "$output" =~ "oci-amd-2" ]]
  [[ "$output" =~ "oci-arm-1" ]]
  [[ "$output" =~ "@tag_project_homelab" ]]
  [[ "$output" =~ "@tag_role_compute" ]]
  [[ "$output" =~ "@tag_role_server" ]]
}

@test "dynamic inventory composes MagicDNS FQDN for ansible_host and maps tailscale_ip" {
  run ansible-inventory -i "${TEST_INV}" --host oci-amd-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oci-amd-1.homelab.ts.net" ]]
  [[ "$output" =~ "198.51.100.10" ]]
}

@test "dynamic inventory rejects corrupted state JSON with non-zero exit code" {
  echo "corrupt-json-payload-{{{{" > "${TMP_STATE}"
  run ansible-inventory -i "${TEST_INV}" --host oci-amd-1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unable to parse" || "$output" =~ "Failed to parse inventory" ]]
}

@test "dynamic inventory handles non-existent or empty state file fail-closed" {
  rm -f "${TMP_STATE}"
  run ansible-inventory -i "${TEST_INV}" --host oci-amd-1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unable to parse" || "$output" =~ "No inventory was parsed" ]]
}

@test "dynamic inventory parses empty resources state into empty host list" {
  cat <<'EOF' > "${TMP_STATE}"
{
  "version": 4,
  "terraform_version": "1.9.0",
  "serial": 1,
  "lineage": "test-empty",
  "outputs": {},
  "resources": []
}
EOF
  run ansible-inventory -i "${TEST_INV}" --graph
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ "oci-amd" ]]
  ! [[ "$output" =~ "oci-arm" ]]
  [[ "$output" =~ "@ungrouped:" ]]
}
