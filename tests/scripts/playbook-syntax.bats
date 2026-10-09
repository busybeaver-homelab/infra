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

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/oci.yml"
  [ "$status" -eq 0 ]
}

@test "oci.yml fails closed when executed without valid production SOPS key" {
  local playbook="$REPO_ROOT/configuration/playbooks/oci.yml"
  [ -f "$playbook" ]

  run env SOPS_AGE_KEY="" GNUPGHOME="/dev/null" ansible-playbook -i "oci," -c local -e ansible_become=false -e ansible_gather_facts=false --check "$playbook"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "SOPS" || "$output" =~ "Failed" || "$output" =~ "error" || "$output" =~ "Could not" || "$output" =~ "unreachable" || "$output" =~ "credentials" ]]
}

@test "mise.toml configures full molecule scenario matrix for ansible testing" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'tasks\."test:ansible:base"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:ansible:restic"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:ansible:oci"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.toml configures fast and clean molecule tasks" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'tasks\."test:ansible:fast"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:ansible:clean"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:ansible:fast:base"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'tasks\."test:ansible:clean:base"' "$mise_config"
  [ "$status" -eq 0 ]
}


@test "base_ubuntu_server defines argument_specs validation metadata" {
  local spec="$REPO_ROOT/configuration/roles/base_ubuntu_server/meta/argument_specs.yml"
  [ -f "$spec" ]

  run yq eval '.argument_specs.main.options.base_ubuntu_server_timezone.type' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "str" ]

  run yq eval '.argument_specs.main.options.base_ubuntu_server_firewall_enabled.type' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "bool" ]
}

@test "ansible.cfg enables ssh pipelining and json fact caching" {
  local cfg="$REPO_ROOT/ansible.cfg"
  [ -f "$cfg" ]

  run grep -E "^pipelining = True" "$cfg"
  [ "$status" -eq 0 ]

  run grep -E "^gathering = smart" "$cfg"
  [ "$status" -eq 0 ]

  run grep -E "^fact_caching = ansible.builtin.jsonfile" "$cfg"
  [ "$status" -eq 0 ]
}

@test "AGENTS.md defines precedence contract and documents full molecule matrix" {
  local doc="$REPO_ROOT/AGENTS.md"
  [ -f "$doc" ]

  run grep -E "Precedence Contract" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "base_ubuntu_server" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "restic_backup" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "molecule test -s oci" "$doc"
  [ "$status" -eq 0 ]
}

@test ".agent/AGENTS.md declares root AGENTS.md supreme precedence" {
  local doc="$REPO_ROOT/.agent/AGENTS.md"
  [ -f "$doc" ]

  run grep -E "Root \`AGENTS\.md\` takes supreme precedence" "$doc"
  [ "$status" -eq 0 ]
}

@test "docs/rootless-docker-investigation.md does not contain machine-specific /Users/ paths" {
  local doc="$REPO_ROOT/docs/rootless-docker-investigation.md"
  [ -f "$doc" ]

  run grep -E "/Users/" "$doc"
  [ "$status" -ne 0 ]
}

@test "docs/runbooks/oci-breakglass-console.md protects breakglass password and tailscale auth key" {
  local doc="$REPO_ROOT/docs/runbooks/oci-breakglass-console.md"
  [ -f "$doc" ]

  # Ensure password clipboard extraction is documented
  run grep -E "mise exec -- sops -d --extract '\\[\"breakglass_password\"\\]'.*\\| pbcopy" "$doc"
  [ "$status" -eq 0 ]

  # Ensure no raw password printing via grep
  run grep -E "grep -E \"breakglass_user\\|breakglass_password\"" "$doc"
  [ "$status" -ne 0 ]

  # Ensure file-based authkey for tailscale up
  run grep -E "tailscale up --ssh --auth-key=\"file:/tmp/ts.key\"" "$doc"
  [ "$status" -eq 0 ]
}

@test "README.md documents Cloudflare R2 state backend and current pinned toolset" {
  local doc="$REPO_ROOT/README.md"
  [ -f "$doc" ]

  # Ensure R2 state backend is documented in architecture diagram
  run grep -E "Cloudflare \(DNS/WAF & R2 State Bucket\)" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "Encrypted State \(AES-GCM\).*CF" "$doc"
  [ "$status" -eq 0 ]

  # Ensure GCS state bucket is no longer in architecture diagram
  run grep -E "State Bucket \(GCS\)" "$doc"
  [ "$status" -ne 0 ]

  # Ensure pinned tool versions match mise.toml
  run grep -E "\*\*OpenTofu\*\*.*\`1\.13\`" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "\*\*Ansible\*\*.*\`14\`" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "\*\*SOPS\*\*.*\`3\.13\`" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "\*\*Python\*\*.*\`3\.14\`" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "\*\*TFLint\*\*.*\`0\.64\`" "$doc"
  [ "$status" -eq 0 ]

  # Ensure all 7 infrastructure modules are documented in repository layout
  run grep -E "azure/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "cloudflare/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "gcp/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "github/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "homelab/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "monitoring/" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "oci/" "$doc"
  [ "$status" -eq 0 ]
}
