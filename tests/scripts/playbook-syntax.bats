#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "configuration/playbooks/base.yml excludes unifi and has play-level become" {
  local playbook="$REPO_ROOT/configuration/playbooks/base.yml"
  [ -f "$playbook" ]

  # Check hosts excludes unifi
  run grep -E "hosts:.*!unifi" "$playbook"
  [ "$status" -eq 0 ]

  # Check play-level become is true
  run grep -E "^  become: true" "$playbook"
  [ "$status" -eq 0 ]
}

@test "configuration/playbooks/common.yml excludes unifi and has play-level become" {
  local playbook="$REPO_ROOT/configuration/playbooks/common.yml"
  [ -f "$playbook" ]

  # Check hosts excludes unifi
  run grep -E "hosts:.*!unifi" "$playbook"
  [ "$status" -eq 0 ]

  # Check play-level become is true
  run grep -E "^  become: true" "$playbook"
  [ "$status" -eq 0 ]
}

@test "configuration/playbooks/oci.yml eliminates failed_when: false on sshd disable" {
  local playbook="$REPO_ROOT/configuration/playbooks/oci.yml"
  [ -f "$playbook" ]

  # Ensure no failed_when: false is present in oci.yml
  run grep "failed_when: false" "$playbook"
  [ "$status" -ne 0 ]

  # Ensure service_facts is used to guard service manipulation
  run grep "ansible.builtin.service_facts" "$playbook"
  [ "$status" -eq 0 ]
}

@test "ansible playbooks pass syntax check" {
  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/base.yml"
  [ "$status" -eq 0 ]

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/common.yml"
  [ "$status" -eq 0 ]

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/site.yml"
  [ "$status" -eq 0 ]
}
