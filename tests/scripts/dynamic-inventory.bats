#!/usr/bin/env bats
# Tests for dynamic Ansible inventory with OpenTofu state fixtures

load 'helpers/test_helper'

FIXTURE_SRC="${REPO_ROOT}/configuration/inventories/fixtures/oci_state.json"
INV_SRC="${REPO_ROOT}/configuration/inventories/test.terraform_state.yml"

setup() {
  setup_tmpdir
  TMP_STATE="${BATS_TEST_TMPDIR}/oci_state.json"
  TEST_INV="${BATS_TEST_TMPDIR}/inventory.terraform_state.yml"
  cp "${FIXTURE_SRC}" "${TMP_STATE}"
  sed "s|/tmp/homelab_test_oci_state.json|${TMP_STATE}|g" "${INV_SRC}" > "${TEST_INV}"
}

teardown() {
  teardown_tmpdir
}

@test "dynamic inventory does not create or rely on /tmp/homelab_test_oci_state.json" {
  rm -f "/tmp/homelab_test_oci_state.json"
  run ansible-inventory -i "${TEST_INV}" --graph
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oci-amd-1" ]]
  [ ! -f "/tmp/homelab_test_oci_state.json" ]
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

@test "dynamic inventory fixture strictly conforms to OpenTofu OCI state schema" {
  run jq -e '[.resources[] | select(.type=="oci_core_instance") | .instances[].attributes | (has("display_name") and has("private_ip") and has("freeform_tags"))] | all' "${FIXTURE_SRC}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "dynamic inventory fixture requires project=homelab tag on all compute resources" {
  run jq -r '.resources[] | select(.type=="oci_core_instance") | .instances[].attributes.freeform_tags.project' "${FIXTURE_SRC}"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  for tag in $output; do
    [ "$tag" = "homelab" ]
  done
}

@test "dynamic inventory matrix correctly classifies multi-node roles and groups" {
  local matrix_state="${REPO_ROOT}/configuration/inventories/fixtures/topology_matrix_state.json"
  local test_inv="${BATS_TEST_TMPDIR}/matrix.terraform_state.yml"
  sed "s|/tmp/homelab_test_oci_state.json|${matrix_state}|g" "${INV_SRC}" > "${test_inv}"

  run ansible-inventory -i "${test_inv}" --graph
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bastion-1" ]]
  [[ "$output" =~ "worker-1" ]]
  [[ "$output" =~ "storage-1" ]]
  [[ "$output" =~ "edge-1" ]]
  [[ "$output" =~ "@tag_role_bastion" ]]
  [[ "$output" =~ "@tag_role_storage" ]]
  [[ "$output" =~ "@tag_role_edge" ]]
}

@test "dynamic inventory matrix extracts distinct private IPs and MagicDNS FQDNs" {
  local matrix_state="${REPO_ROOT}/configuration/inventories/fixtures/topology_matrix_state.json"
  local test_inv="${BATS_TEST_TMPDIR}/matrix.terraform_state.yml"
  sed "s|/tmp/homelab_test_oci_state.json|${matrix_state}|g" "${INV_SRC}" > "${test_inv}"

  run ansible-inventory -i "${test_inv}" --host storage-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "storage-1.homelab.ts.net" ]]
  [[ "$output" =~ "198.51.100.50" ]]
}

@test "dynamic inventory topology matrix fixture strictly conforms to OpenTofu OCI state schema" {
  local matrix_state="${REPO_ROOT}/configuration/inventories/fixtures/topology_matrix_state.json"
  run jq -e '[.resources[] | select(.type=="oci_core_instance") | .instances[].attributes | (has("display_name") and has("private_ip") and has("freeform_tags"))] | all' "${matrix_state}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "dynamic inventory topology matrix fixture requires project=homelab tag on all compute resources" {
  local matrix_state="${REPO_ROOT}/configuration/inventories/fixtures/topology_matrix_state.json"
  run jq -r '.resources[] | select(.type=="oci_core_instance") | .instances[].attributes.freeform_tags.project' "${matrix_state}"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  for tag in $output; do
    [ "$tag" = "homelab" ]
  done
}

