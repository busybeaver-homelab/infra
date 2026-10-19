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
  [[ "$output" =~ "oci-amd-1" ]] || false
  [ ! -f "/tmp/homelab_test_oci_state.json" ]
}

@test "dynamic inventory parses test state fixture and outputs expected hosts and groups" {
  run ansible-inventory -i "${TEST_INV}" --graph
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oci-amd-1" ]] || false
  [[ "$output" =~ "oci-amd-2" ]] || false
  [[ "$output" =~ "oci-arm-1" ]] || false
  [[ "$output" =~ "@tag_project_homelab" ]] || false
  [[ "$output" =~ "@tag_role_compute" ]] || false
  [[ "$output" =~ "@tag_role_server" ]]
}

@test "dynamic inventory composes MagicDNS FQDN for ansible_host and maps tailscale_ip" {
  run ansible-inventory -i "${TEST_INV}" --host oci-amd-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "oci-amd-1.example.ts.net" ]] || false
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
  [[ "$output" =~ "Unable to parse" || "$output" =~ "No inventory was parsed" || "$output" =~ "Failed to parse inventory" ]]
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
  [[ "$output" =~ "bastion-1" ]] || false
  [[ "$output" =~ "worker-1" ]] || false
  [[ "$output" =~ "storage-1" ]] || false
  [[ "$output" =~ "edge-1" ]] || false
  [[ "$output" =~ "@tag_role_bastion" ]] || false
  [[ "$output" =~ "@tag_role_storage" ]] || false
  [[ "$output" =~ "@tag_role_edge" ]]
}

@test "dynamic inventory matrix extracts distinct private IPs and MagicDNS FQDNs" {
  local matrix_state="${REPO_ROOT}/configuration/inventories/fixtures/topology_matrix_state.json"
  local test_inv="${BATS_TEST_TMPDIR}/matrix.terraform_state.yml"
  sed "s|/tmp/homelab_test_oci_state.json|${matrix_state}|g" "${INV_SRC}" > "${test_inv}"

  run ansible-inventory -i "${test_inv}" --host storage-1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "storage-1.example.ts.net" ]] || false
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

@test "dynamic inventory classifies OCI instances into @oci and @cloud groups" {
  run ansible-inventory -i "${TEST_INV}" --graph
  [ "$status" -eq 0 ]
  grep -q "@oci:" <<< "$output"
  grep -q "@cloud:" <<< "$output"
}

@test "dynamic inventory parses GCP compute instance from state fixture into @gcp and @cloud groups" {
  local gcp_fixture="${REPO_ROOT}/configuration/inventories/fixtures/gcp_state.json"
  local gcp_inv="${REPO_ROOT}/configuration/inventories/gcp.terraform_state.yml"
  [ -f "${gcp_fixture}" ]
  [ -f "${gcp_inv}" ]
  local test_inv="${BATS_TEST_TMPDIR}/gcp.terraform_state.yml"
  yq eval ".backend_type = \"local\" | .backend_config = {\"path\": \"${gcp_fixture}\"}" "${gcp_inv}" > "${test_inv}"

  run ansible-inventory -i "${test_inv}" --graph
  [ "$status" -eq 0 ]
  grep -q "gcp-default-vm" <<< "$output"
  grep -q "@gcp:" <<< "$output"
  grep -q "@cloud:" <<< "$output"
  grep -q "@tag_project_homelab" <<< "$output"
}

@test "dynamic inventory composes MagicDNS FQDN and tailscale_ip for GCP compute instance" {
  local gcp_fixture="${REPO_ROOT}/configuration/inventories/fixtures/gcp_state.json"
  local gcp_inv="${REPO_ROOT}/configuration/inventories/gcp.terraform_state.yml"
  [ -f "${gcp_fixture}" ]
  [ -f "${gcp_inv}" ]
  local test_inv="${BATS_TEST_TMPDIR}/gcp.terraform_state.yml"
  yq eval ".backend_type = \"local\" | .backend_config = {\"path\": \"${gcp_fixture}\"}" "${gcp_inv}" > "${test_inv}"

  run ansible-inventory -i "${test_inv}" --host gcp-default-vm
  [ "$status" -eq 0 ]
  grep -q "gcp-default-vm.example.ts.net" <<< "$output"
  grep -q "198.51.100.40" <<< "$output"
}

@test "dynamic inventory GCP fixture strictly conforms to OpenTofu google_compute_instance state schema and project=homelab label" {
  local gcp_fixture="${REPO_ROOT}/configuration/inventories/fixtures/gcp_state.json"
  [ -f "${gcp_fixture}" ]
  run jq -e '[.resources[] | select(.type=="google_compute_instance") | .instances[].attributes | (has("name") and has("machine_type") and has("network_interface") and (.labels.project == "homelab"))] | all' "${gcp_fixture}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "configuration/inventories/gcp.terraform_state.yml configures R2 state backend for GCP" {
  local gcp_inv="${REPO_ROOT}/configuration/inventories/gcp.terraform_state.yml"
  [ -f "${gcp_inv}" ]
  run yq eval '.backend_config.key' "${gcp_inv}"
  [ "$status" -eq 0 ]
  [ "$output" = "homelab-infra/state/gcp/tofu.tfstate" ]
}

@test "configuration/inventories/test_gcp.terraform_state.yml parses GCP state fixture in CI local mode" {
  local gcp_fixture="${REPO_ROOT}/configuration/inventories/fixtures/gcp_state.json"
  local test_gcp_inv_src="${REPO_ROOT}/configuration/inventories/test_gcp.terraform_state.yml"
  [ -f "${gcp_fixture}" ]
  [ -f "${test_gcp_inv_src}" ]
  local tmp_gcp_state="${BATS_TEST_TMPDIR}/gcp_state.json"
  local test_gcp_inv="${BATS_TEST_TMPDIR}/test_gcp.terraform_state.yml"
  cp "${gcp_fixture}" "${tmp_gcp_state}"
  sed "s|/tmp/homelab_test_gcp_state.json|${tmp_gcp_state}|g" "${test_gcp_inv_src}" > "${test_gcp_inv}"

  run ansible-inventory -i "${test_gcp_inv}" --graph
  [ "$status" -eq 0 ]
  grep -q "gcp-default-vm" <<< "$output"
  grep -q "@gcp:" <<< "$output"
  grep -q "@cloud:" <<< "$output"

  run ansible-inventory -i "${test_gcp_inv}" --host gcp-default-vm
  [ "$status" -eq 0 ]
  grep -q "gcp-default-vm.example.ts.net" <<< "$output"
  grep -q "198.51.100.40" <<< "$output"
}

@test "scripts/generate-inventory.sh renders valid Ansible inventory from --from-json fixtures" {
  local script="${REPO_ROOT}/scripts/generate-inventory.sh"
  [ -x "${script}" ]

  local oci_json="${BATS_TEST_TMPDIR}/oci_inventory.json"
  local gcp_json="${BATS_TEST_TMPDIR}/gcp_inventory.json"
  local out_yml="${BATS_TEST_TMPDIR}/hosts.generated.yml"

  cat > "${oci_json}" <<'EOF'
{
  "group": "oci",
  "hosts": {
    "oci-amd-1": {
      "ansible_host": "192.0.2.10",
      "private_ip": "192.0.2.10",
      "role": "compute"
    },
    "oci-arm-1": {
      "ansible_host": "192.0.2.11",
      "private_ip": "192.0.2.11",
      "role": "compute"
    }
  }
}
EOF

  cat > "${gcp_json}" <<'EOF'
{
  "group": "gcp",
  "hosts": {
    "gcp-default-vm": {
      "ansible_host": "198.51.100.40",
      "private_ip": "198.51.100.40",
      "role": "compute"
    }
  }
}
EOF

  run "${script}" --output "${out_yml}" --from-json "${oci_json}" --from-json "${gcp_json}"
  [ "$status" -eq 0 ]
  [ -f "${out_yml}" ]

  run ansible-inventory -i "${out_yml}" --graph
  [ "$status" -eq 0 ]
  grep -q "@cloud:" <<< "$output"
  grep -q "@oci:" <<< "$output"
  grep -q "@gcp:" <<< "$output"
  grep -q "oci-amd-1" <<< "$output"
  grep -q "oci-arm-1" <<< "$output"
  grep -q "gcp-default-vm" <<< "$output"

  run bash -c "ansible-inventory -i '${out_yml}' --list 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(jq -r '._meta.hostvars["oci-amd-1"].ansible_host' <<< "$output")" = "192.0.2.10" ]
  [ "$(jq -r '._meta.hostvars["oci-arm-1"].ansible_host' <<< "$output")" = "192.0.2.11" ]
  [ "$(jq -r '._meta.hostvars["gcp-default-vm"].ansible_host' <<< "$output")" = "198.51.100.40" ]
}

@test "scripts/generate-inventory.sh fails closed when zero hosts are discovered" {
  local script="${REPO_ROOT}/scripts/generate-inventory.sh"
  local empty_json="${BATS_TEST_TMPDIR}/empty_inventory.json"
  local out_yml="${BATS_TEST_TMPDIR}/hosts.empty.yml"

  cat > "${empty_json}" <<'EOF'
{
  "group": "oci",
  "hosts": {}
}
EOF

  run "${script}" --output "${out_yml}" --from-json "${empty_json}"
  [ "$status" -ne 0 ]
  [ ! -f "${out_yml}" ]
}

@test "configuration/inventories/README.md documents hosts.yml and hosts.generated.yml and names only existing files (R2-ANS-03)" {
  local readme="${REPO_ROOT}/configuration/inventories/README.md"
  local gen_script="${REPO_ROOT}/scripts/generate-inventory.sh"
  [ -f "${readme}" ]
  [ -f "${gen_script}" ]

  run grep -F "hosts.yml" "${readme}"
  [ "$status" -eq 0 ]

  run grep -F "hosts.generated.yml" "${readme}"
  [ "$status" -eq 0 ]

  run grep -F "scripts/generate-inventory.sh" "${readme}"
  [ "$status" -eq 0 ]

  for stale in "01-Homelab-Static.yml" "02-Cloud-Dynamic.yml" "99-Dynamic-Inventory.ini" "--allow-sops-fallback"; do
    run grep -F "${stale}" "${readme}"
    [ "$status" -ne 0 ]
  done

  run grep -F "configuration/inventory/hosts.generated.yml" "${gen_script}"
  [ "$status" -ne 0 ]
  run grep -F "configuration/inventories/hosts.generated.yml" "${gen_script}"
  [ "$status" -eq 0 ]

  local token
  while IFS= read -r token; do
    [ -n "${token}" ] || continue
    if [ "${token}" = "hosts.generated.yml" ] || [ "${token}" = "configuration/inventories/hosts.generated.yml" ]; then
      continue
    fi
    [ -f "${REPO_ROOT}/configuration/inventories/${token}" ] || [ -f "${REPO_ROOT}/${token}" ]
  done < <(grep -Eo '`[A-Za-z0-9_./-]+\.(yml|yaml|ini|sh)`' "${readme}" | tr -d '`' | sort -u)
}

@test "cloud.yml, homelab.yml, unifi.yml, and site.yml enforce per-group preflight assertions citing STD-AN-29 (R2-ANS-03)" {
  local cloud_pb="${REPO_ROOT}/configuration/playbooks/cloud.yml"
  local homelab_pb="${REPO_ROOT}/configuration/playbooks/homelab.yml"
  local unifi_pb="${REPO_ROOT}/configuration/playbooks/unifi.yml"
  local site_pb="${REPO_ROOT}/configuration/playbooks/site.yml"

  local cloud_that
  cloud_that="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].that[0]' "${cloud_pb}")"
  [[ "${cloud_that}" == *"groups['oci']"* ]] || false
  [[ "${cloud_that}" == *"groups['gcp']"* ]] || false
  local cloud_msg
  cloud_msg="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].fail_msg' "${cloud_pb}")"
  [[ "${cloud_msg}" == *"STD-AN-29"* ]] || false

  local homelab_that
  homelab_that="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].that[0]' "${homelab_pb}")"
  [[ "${homelab_that}" == *"groups['homelab']"* ]] || false
  local homelab_msg
  homelab_msg="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].fail_msg' "${homelab_pb}")"
  [[ "${homelab_msg}" == *"STD-AN-29"* ]] || false

  local unifi_that
  unifi_that="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].that[0]' "${unifi_pb}")"
  [[ "${unifi_that}" == *"groups['unifi']"* ]] || false
  local unifi_msg
  unifi_msg="$(yq -r '.[0].tasks[0]["ansible.builtin.assert"].fail_msg' "${unifi_pb}")"
  [[ "${unifi_msg}" == *"STD-AN-29"* ]] || false

  run yq -r '.[] | select(.["ansible.builtin.import_playbook"] == "homelab.yml") | .vars.allow_empty_inventory' "${site_pb}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq -r '.[] | select(.["ansible.builtin.import_playbook"] == "unifi.yml") | .vars.allow_empty_inventory' "${site_pb}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "homelab.yml alone fails on an empty homelab inventory while site.yml succeeds across preflights (R2-ANS-03)" {
  local hosts_yml="${REPO_ROOT}/configuration/inventories/hosts.yml"
  local homelab_pb="${REPO_ROOT}/configuration/playbooks/homelab.yml"
  local unifi_pb="${REPO_ROOT}/configuration/playbooks/unifi.yml"
  local cloud_pb="${REPO_ROOT}/configuration/playbooks/cloud.yml"
  local site_pb="${REPO_ROOT}/configuration/playbooks/site.yml"
  local script="${REPO_ROOT}/scripts/generate-inventory.sh"

  run ansible-playbook -i "${hosts_yml}" "${homelab_pb}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STD-AN-29"* ]] || false

  run ansible-playbook -i "${hosts_yml}" "${unifi_pb}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STD-AN-29"* ]] || false

  run ansible-playbook -i "${hosts_yml}" "${cloud_pb}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STD-AN-29"* ]] || false

  local oci_json="${BATS_TEST_TMPDIR}/oci_inventory.json"
  local out_yml="${BATS_TEST_TMPDIR}/hosts.generated.yml"
  cat > "${oci_json}" <<'EOF'
{
  "group": "oci",
  "hosts": {
    "oci-amd-1": {
      "ansible_host": "192.0.2.10",
      "private_ip": "192.0.2.10",
      "role": "compute"
    }
  }
}
EOF
  run "${script}" --output "${out_yml}" --from-json "${oci_json}"
  [ "$status" -eq 0 ]

  run ansible-playbook -i "${hosts_yml}" -i "${out_yml}" --tags preflight --skip-tags always "${homelab_pb}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"STD-AN-29"* ]] || false

  run ansible-playbook -i "${hosts_yml}" -i "${out_yml}" --tags preflight --skip-tags always "${site_pb}"
  [ "$status" -eq 0 ]
}

