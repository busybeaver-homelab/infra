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
