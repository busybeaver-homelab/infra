#!/usr/bin/env bats
# Tests for Ansible inventory synthesis (scripts/generate-inventory.sh) and inventory preflights

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "unused terraform_state inventory plugin files, state fixtures, and plugin references are removed (REV2-P2-1)" {
  local removed
  for removed in \
    "configuration/inventories/terraform.terraform_state.yml" \
    "configuration/inventories/gcp.terraform_state.yml" \
    "configuration/inventories/test.terraform_state.yml" \
    "configuration/inventories/test_gcp.terraform_state.yml" \
    "configuration/inventories/fixtures/oci_state.json" \
    "configuration/inventories/fixtures/gcp_state.json" \
    "configuration/inventories/fixtures/topology_matrix_state.json"; do
    [ ! -e "${REPO_ROOT}/${removed}" ]
  done

  run grep -E 'terraform_state|cloud\.terraform' \
    "${REPO_ROOT}/ansible.cfg" \
    "${REPO_ROOT}/configuration/roles/requirements.yml" \
    "${REPO_ROOT}/.github/workflows/ci.yml" \
    "${REPO_ROOT}/README.md" \
    "${REPO_ROOT}/infrastructure/README.md"
  [ "$status" -ne 0 ]
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

