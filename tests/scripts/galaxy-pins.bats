#!/usr/bin/env bats
# Tests for REV2-P3-6 (Galaxy pins, project-local paths, collection migration)
# and REV2-P3-7 (Molecule hygiene, runtime passwords, fail-closed SOPS corruption test)

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "ansible.cfg sets project-local roles_path and collections_path without ~/.ansible or .." {
  local cfg="${REPO_ROOT}/ansible.cfg"
  [ -f "$cfg" ]

  run grep -E '^roles_path = configuration/roles:configuration/\.galaxy/roles$' "$cfg"
  [ "$status" -eq 0 ]

  run grep -E '^collections_path = configuration/\.galaxy/collections$' "$cfg"
  [ "$status" -eq 0 ]

  run grep -F '~/.ansible' "$cfg"
  [ "$status" -ne 0 ]

  run grep -E 'roles_path.*:\.\.' "$cfg"
  [ "$status" -ne 0 ]
}

@test ".gitignore ignores configuration/.galaxy/ and .ansible/" {
  local gitignore="${REPO_ROOT}/.gitignore"
  [ -f "$gitignore" ]

  run grep -Fx 'configuration/.galaxy/' "$gitignore"
  [ "$status" -eq 0 ]

  run grep -Fx '.ansible/' "$gitignore"
  [ "$status" -eq 0 ]
}

@test "requirements.yml pins all roles and collections to exact X.Y.Z versions" {
  local req="${REPO_ROOT}/configuration/roles/requirements.yml"
  [ -f "$req" ]

  run yq eval '.roles[].version' "$req"
  [ "$status" -eq 0 ]
  while IFS= read -r ver; do
    [ -n "$ver" ] || continue
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
  done <<<"$output"

  run yq eval '.collections[].version' "$req"
  [ "$status" -eq 0 ]
  while IFS= read -r ver; do
    [ -n "$ver" ] || continue
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
  done <<<"$output"
}

@test "requirements.yml removes deprecated/unmaintained roles and pins devsec.hardening and community.general" {
  local req="${REPO_ROOT}/configuration/roles/requirements.yml"
  [ -f "$req" ]

  for banned_role in "dev-sec.os-hardening" "dev-sec.ssh-hardening" "singleplatform-eng.users" "ajsalminen.hosts"; do
    run grep -F "$banned_role" "$req"
    [ "$status" -ne 0 ]
  done

  run yq eval '.collections[] | select(.name == "devsec.hardening") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "11.0.0" ]

  run yq eval '.collections[] | select(.name == "community.general") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "13.5.0" ]
}

@test "installed Galaxy roles and collections in configuration/.galaxy match requirements.yml pins" {
  local req="${REPO_ROOT}/configuration/roles/requirements.yml"
  local roles_dir="${REPO_ROOT}/configuration/.galaxy/roles"
  local colls_dir="${REPO_ROOT}/configuration/.galaxy/collections/ansible_collections"

  if [ ! -d "$roles_dir" ] || [ ! -d "$colls_dir" ]; then
    skip "configuration/.galaxy is not populated in this environment"
  fi

  while IFS=: read -r rname rver; do
    [ -n "$rname" ] || continue
    [ -d "${roles_dir}/${rname}" ]
    run yq eval '.version' "${roles_dir}/${rname}/meta/.galaxy_install_info"
    [ "$status" -eq 0 ]
    [ "$output" = "$rver" ]
  done < <(yq eval '.roles[] | .name + ":" + .version' "$req")

  while IFS=: read -r cname cver; do
    [ -n "$cname" ] || continue
    local cpath="${cname//.//}"
    local manifest="${colls_dir}/${cpath}/MANIFEST.json"
    [ -f "$manifest" ]
    run jq -r '.collection_info.version' "$manifest"
    [ "$status" -eq 0 ]
    [ "$output" = "$cver" ]
  done < <(yq eval '.collections[] | .name + ":" + .version' "$req")
}

@test "cloud.yml uses devsec.hardening.os_hardening and removes deprecated roles" {
  local cloud_pb="${REPO_ROOT}/configuration/playbooks/cloud.yml"
  [ -f "$cloud_pb" ]

  run grep -F "devsec.hardening.os_hardening" "$cloud_pb"
  [ "$status" -eq 0 ]

  for removed in "ajsalminen.hosts" "dev-sec.os-hardening" "dev-sec.ssh-hardening" "singleplatform-eng.users"; do
    run grep -F "$removed" "$cloud_pb"
    [ "$status" -ne 0 ]
  done
}

@test "base_ubuntu_server manages /etc/hosts via templates/hosts.j2" {
  local tpl="${REPO_ROOT}/configuration/roles/base_ubuntu_server/templates/hosts.j2"
  local tasks="${REPO_ROOT}/configuration/roles/base_ubuntu_server/tasks/main.yml"
  [ -f "$tpl" ]
  [ -f "$tasks" ]

  run grep -F "ansible_managed | ansible.builtin.comment" "$tpl"
  [ "$status" -eq 0 ]

  run grep -F "dest: /etc/hosts" "$tasks"
  [ "$status" -eq 0 ]

  run grep -F "molecule_unsafe_writes" "$tasks"
  [ "$status" -eq 0 ]
}

@test "all Molecule scenarios use project-local .galaxy paths, disable prerun, and never use ~/.ansible/roles" {
  local scenarios=(
    "configuration/roles/base_ubuntu_server/molecule/default/molecule.yml"
    "configuration/roles/restic_backup/molecule/default/molecule.yml"
    "configuration/roles/docker_compose_service/molecule/default/molecule.yml"
    "configuration/molecule/oci/molecule.yml"
    "configuration/molecule/gcp/molecule.yml"
    "configuration/molecule/homelab/molecule.yml"
  )

  for rel in "${scenarios[@]}"; do
    local mol="${REPO_ROOT}/${rel}"
    [ -f "$mol" ]

    run grep -F '~/.ansible/roles' "$mol"
    [ "$status" -ne 0 ]

    run grep -Fx 'prerun: false' "$mol"
    [ "$status" -eq 0 ]

    run grep -F '.galaxy/roles' "$mol"
    [ "$status" -eq 0 ]

    run grep -F '.galaxy/collections' "$mol"
    [ "$status" -eq 0 ]
  done
}

@test "dead configuration/molecule/site scenario is removed (R2-ANS-11)" {
  [ ! -e "${REPO_ROOT}/configuration/molecule/site" ]
}

@test "restic_backup Molecule scenario uses runtime-generated passwords instead of hardcoded strings (R2-ANS-11)" {
  local conv="${REPO_ROOT}/configuration/roles/restic_backup/molecule/default/converge.yml"
  local ver="${REPO_ROOT}/configuration/roles/restic_backup/molecule/default/verify.yml"
  [ -f "$conv" ]
  [ -f "$ver" ]

  run grep -F "test-primary-encryption-password-molecule!" "$conv" "$ver"
  [ "$status" -ne 0 ]

  run grep -F "test-secondary-encryption-password-molecule!" "$conv" "$ver"
  [ "$status" -ne 0 ]

  run grep -F "lookup('ansible.builtin.password', '/tmp/molecule-restic-primary-pass'" "$conv"
  [ "$status" -eq 0 ]

  run grep -F "lookup('ansible.builtin.password', '/tmp/molecule-restic-dr-pass'" "$conv"
  [ "$status" -eq 0 ]

  run grep -F "lookup('ansible.builtin.password', '/tmp/molecule-restic-primary-pass'" "$ver"
  [ "$status" -eq 0 ]
}

@test "configuration tree contains no literal AGE-SECRET-KEY- strings and fault_injection corrupts a copy of credentials.ci.sops.yaml" {
  local prefix="AGE-SECRET-"
  local suffix="KEY-"
  run grep -rn "${prefix}${suffix}" "${REPO_ROOT}/configuration/"
  [ "$status" -ne 0 ]

  local fault="${REPO_ROOT}/configuration/molecule/homelab/fault_injection.yml"
  [ -f "$fault" ]

  run grep -F "credentials.ci.sops.yaml" "$fault"
  [ "$status" -eq 0 ]
}
