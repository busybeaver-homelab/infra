#!/usr/bin/env bats

load 'helpers/test_helper'

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

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/homelab.yml"
  [ "$status" -eq 0 ]

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/site.yml"
  [ "$status" -eq 0 ]

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/oci.yml"
  [ "$status" -eq 0 ]

  run mise exec -- ansible-playbook --syntax-check "$REPO_ROOT/configuration/playbooks/unifi.yml"
  [ "$status" -eq 0 ]
}

@test "configuration/molecule/site configures mock harness for site and unifi playbooks" {
  local mol="$REPO_ROOT/configuration/molecule/site/molecule.yml"
  local conv="$REPO_ROOT/configuration/molecule/site/converge.yml"
  local ver="$REPO_ROOT/configuration/molecule/site/verify.yml"

  [ -f "$mol" ]
  [ -f "$conv" ]
  [ -f "$ver" ]

  run yq eval '.platforms[0].groups[]' "$mol"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "homelab" ]]
  [[ "$output" =~ "oci" ]]
  [[ "$output" =~ "unifi" ]]

  run grep "site.yml --syntax-check" "$conv"
  [ "$status" -eq 0 ]

  run grep "unifi.yml --syntax-check" "$conv"
  [ "$status" -eq 0 ]
}

@test "configuration/molecule/homelab configures Ubuntu 26.04 docker platform for homelab" {
  local mol="$REPO_ROOT/configuration/molecule/homelab/molecule.yml"
  [ -f "$mol" ]

  run yq eval '.platforms[0].groups[0]' "$mol"
  [ "$status" -eq 0 ]
  [ "$output" = "homelab" ]

  run yq eval '.platforms[0].name' "$mol"
  [ "$status" -eq 0 ]
  [ "$output" = "homelab-ubuntu-server-26" ]
}

@test "all molecule scenarios explicitly enforce idempotence in test_sequence" {
  local scenarios=(
    "configuration/roles/base_ubuntu_server/molecule/default/molecule.yml"
    "configuration/roles/restic_backup/molecule/default/molecule.yml"
    "configuration/molecule/oci/molecule.yml"
    "configuration/molecule/homelab/molecule.yml"
  )

  for mol_file in "${scenarios[@]}"; do
    local full_path="$REPO_ROOT/$mol_file"
    [ -f "$full_path" ]
    run yq eval '.scenario.test_sequence[]' "$full_path"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "idempotence" ]]
    [[ "$output" =~ "converge" ]]
  done
}

@test "molecule scenarios verify handler execution and service daemon states" {
  local base_verify="$REPO_ROOT/configuration/roles/base_ubuntu_server/molecule/default/verify.yml"
  local homelab_verify="$REPO_ROOT/configuration/molecule/homelab/verify.yml"

  [ -f "$base_verify" ]
  [ -f "$homelab_verify" ]

  # base_ubuntu_server must assert firewall reload and after.rules
  run grep -E "ufw reload|after\.rules" "$base_verify"
  [ "$status" -eq 0 ]

  # homelab must assert docker service state
  run grep -E "docker\.service|systemctl is-active docker" "$homelab_verify"
  [ "$status" -eq 0 ]
}

@test "configuration/molecule/oci/converge.yml isolates swapfile path and enables test mode for container CI" {
  local conv="$REPO_ROOT/configuration/molecule/oci/converge.yml"
  [ -f "$conv" ]

  run yq eval '.[0].vars.swap_test_mode' "$conv"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.[0].vars.swap_file_path' "$conv"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "/swapfile" ]

  run yq eval '.[0].vars.swap_file_size_mb' "$conv"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
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

@test "restic_backup defines argument_specs validation metadata" {
  local spec="$REPO_ROOT/configuration/roles/restic_backup/meta/argument_specs.yml"
  [ -f "$spec" ]

  run yq eval '.argument_specs.main.options.restic_backup_repository.type' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "str" ]

  run yq eval '.argument_specs.main.options.restic_backup_password.type' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "str" ]

  run yq eval '.argument_specs.main.options.restic_backup_password.no_log' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.argument_specs.main.options.restic_backup_paths.type' "$spec"
  [ "$status" -eq 0 ]
  [ "$output" = "list" ]
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

  run grep -E "molecule test -s homelab" "$doc"
  [ "$status" -eq 0 ]
}

@test "ci.yml runs fail-closed ansible dry-run and includes homelab scenario in molecule matrix" {
  local ci="$REPO_ROOT/.github/workflows/ci.yml"
  [ -f "$ci" ]

  # Ensure continue-on-error is not set on ansible-check steps
  run yq eval '.jobs.ansible-check.steps[].continue-on-error' "$ci"
  [ "$status" -eq 0 ]
  run grep -E "true" <<< "$output"
  [ "$status" -ne 0 ]

  # Ensure ephemeral target is used for check mode
  run grep -E -- "-i \"localhost,\"" "$ci"
  [ "$status" -eq 0 ]
  run grep -E -- "-c local" "$ci"
  [ "$status" -eq 0 ]

  # Ensure homelab scenario is in molecule matrix
  run yq eval '.jobs.molecule.strategy.matrix.scenario[]' "$ci"
  [ "$status" -eq 0 ]
  run grep -E "^homelab$" <<< "$output"
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
  if is_git_crypt_encrypted "$doc"; then
    skip "docs/rootless-docker-investigation.md is git-crypt encrypted in CI environment"
  fi

  run grep -E "/Users/" "$doc"
  [ "$status" -ne 0 ]
}

@test "docs/runbooks/oci-breakglass-console.md protects breakglass password and tailscale auth key" {
  local doc="$REPO_ROOT/docs/runbooks/oci-breakglass-console.md"
  [ -f "$doc" ]
  if is_git_crypt_encrypted "$doc"; then
    skip "docs/runbooks/oci-breakglass-console.md is git-crypt encrypted in CI environment"
  fi

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

  # Ensure all 8 infrastructure modules are documented in repository layout
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

  run grep -E "mesh/" "$doc"
  [ "$status" -eq 0 ]
}

@test "restic_backup defaults define dual-target variables" {
  local defaults="$REPO_ROOT/configuration/roles/restic_backup/defaults/main.yml"
  [ -f "$defaults" ]
  run grep "restic_backup_secondary_enabled:" "$defaults"
  [ "$status" -eq 0 ]
  run grep "restic_backup_secondary_repository:" "$defaults"
  [ "$status" -eq 0 ]
  run grep "restic_backup_secondary_password:" "$defaults"
  [ "$status" -eq 0 ]
  run grep "restic_backup_credstore_dir:" "$defaults"
  [ "$status" -eq 0 ]
}

@test "restic_backup tasks deploy primary.env, secondary.env, and encrypted credentials" {
  local tasks="$REPO_ROOT/configuration/roles/restic_backup/tasks/main.yml"
  [ -f "$tasks" ]
  run grep "primary.env" "$tasks"
  [ "$status" -eq 0 ]
  run grep "secondary.env" "$tasks"
  [ "$status" -eq 0 ]
  run grep "restic-credential-sync" "$tasks"
  [ "$status" -eq 0 ]
}

@test "configuration/group_vars/oci.yml wires dual restic backup targets" {
  local oci_vars="$REPO_ROOT/configuration/group_vars/oci.yml"
  [ -f "$oci_vars" ]
  run grep "restic_backup_secondary_enabled: true" "$oci_vars"
  [ "$status" -eq 0 ]
  run grep "cloudflare_restic.s3_endpoint" "$oci_vars"
  [ "$status" -eq 0 ]
  run grep "cloudflare_restic.bucket" "$oci_vars"
  [ "$status" -eq 0 ]
  run grep "cloudflare_restic.s3_access_key_id" "$oci_vars"
  [ "$status" -eq 0 ]
  run grep "cloudflare_restic.password" "$oci_vars"
  [ "$status" -eq 0 ]
}

@test "AGENTS.md mandates automated pull request creation when separate branch is pushed" {
  local doc="$REPO_ROOT/AGENTS.md"
  [ -f "$doc" ]

  run grep -E "Automated Pull Request Creation" "$doc"
  [ "$status" -eq 0 ]

  run grep -E "Conventional Commits" "$doc"
  [ "$status" -eq 0 ]
}

@test "configuration/roles/requirements.yml declares required collections and pins" {
  local req="$REPO_ROOT/configuration/roles/requirements.yml"
  [ -f "$req" ]

  run yq eval '.collections[] | select(.name == "community.sops") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "2.5.0" ]

  run yq eval '.collections[] | select(.name == "ansible.posix") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "2.2.2" ]

  run yq eval '.collections[] | select(.name == "community.general") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "10.4.0" ]

  run yq eval '.collections[] | select(.name == "cloud.terraform") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "4.0.0" ]

  run yq eval '.collections[] | select(.name == "community.docker") | .version' "$req"
  [ "$status" -eq 0 ]
  [ "$output" = "5.2.1" ]
}

@test "all collection references in configuration are declared in requirements.yml or ansible.builtin" {
  local req="$REPO_ROOT/configuration/roles/requirements.yml"
  [ -f "$req" ]

  run mise exec -- python3 -c '
import os, re, yaml, sys

with open("configuration/roles/requirements.yml") as f:
    req = yaml.safe_load(f)
declared = {c["name"] for c in req.get("collections", [])}
declared.add("ansible.builtin")
declared.add("ansible.legacy")

pattern = re.compile(r"^\s*(?:-\s+)?([a-z0-9_]+\.[a-z0-9_]+)\.[a-z0-9_]+:")
plugin_pattern = re.compile(r"^\s*plugin:\s+([a-z0-9_]+\.[a-z0-9_]+)\.[a-z0-9_]+")
unknown = set()

dirs_to_check = [
    "configuration/playbooks",
    "configuration/roles",
    "configuration/molecule",
    "configuration/inventories",
]

for d in dirs_to_check:
    for root, dirs, files in os.walk(d):
        if os.path.basename(root) in ("defaults", "meta", "vars", "fixtures"):
            continue
        for file in files:
            if file.endswith((".yml", ".yaml")):
                filepath = os.path.join(root, file)
                with open(filepath, "r", encoding="utf-8") as f:
                    for line in f:
                        match = pattern.match(line) or plugin_pattern.match(line)
                        if match:
                            coll = match.group(1)
                            if coll not in declared:
                                unknown.add(f"{filepath}: {coll}")

if unknown:
    print("Found undeclared collections:", unknown, file=sys.stderr)
    sys.exit(1)
'
  [ "$status" -eq 0 ]
}

@test "all molecule scenarios configure unique container platform names" {
  local scenarios=(
    "configuration/roles/base_ubuntu_server/molecule/default/molecule.yml:base-ubuntu-server-26"
    "configuration/roles/restic_backup/molecule/default/molecule.yml:restic-ubuntu-server-26"
    "configuration/molecule/oci/molecule.yml:oci-ubuntu-server-26"
    "configuration/molecule/homelab/molecule.yml:homelab-ubuntu-server-26"
  )

  local names=()
  for item in "${scenarios[@]}"; do
    IFS=':' read -r path expected <<< "$item"
    local full_path="$REPO_ROOT/$path"
    [ -f "$full_path" ]

    run yq eval '.platforms[0].name' "$full_path"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    names+=("$output")
  done

  # Verify all names are unique
  local unique_count
  unique_count=$(printf "%s\n" "${names[@]}" | sort -u | wc -l | tr -d ' ')
  [ "$unique_count" -eq "${#names[@]}" ]
}

@test "all molecule scenarios configure provisioner pipelining and task profiling" {
  local scenarios=(
    "configuration/roles/base_ubuntu_server/molecule/default/molecule.yml"
    "configuration/roles/restic_backup/molecule/default/molecule.yml"
    "configuration/molecule/oci/molecule.yml"
    "configuration/molecule/homelab/molecule.yml"
  )

  for path in "${scenarios[@]}"; do
    local full_path="$REPO_ROOT/$path"
    [ -f "$full_path" ]

    run yq eval '.provisioner.config_options.connection.pipelining' "$full_path"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]

    run yq eval '.provisioner.config_options.defaults.callbacks_enabled' "$full_path"
    [ "$status" -eq 0 ]
    [ "$output" = "profile_tasks" ]
  done
}

@test "all molecule scenarios configure persistent host apt archive cache mounts" {
  local scenarios=(
    "configuration/roles/base_ubuntu_server/molecule/default/molecule.yml:.cache/apt/archives"
    "configuration/roles/restic_backup/molecule/default/molecule.yml:.cache/apt/archives"
    "configuration/molecule/oci/molecule.yml:.cache/apt/oci/archives"
    "configuration/molecule/homelab/molecule.yml:.cache/apt/homelab/archives"
  )

  for item in "${scenarios[@]}"; do
    IFS=':' read -r path expected_suffix <<< "$item"
    local full_path="$REPO_ROOT/$path"
    [ -f "$full_path" ]

    run yq eval '.platforms[0].volumes[]' "$full_path"
    [ "$status" -eq 0 ]
    run grep -F "/var/cache/apt/archives:rw" <<< "$output"
    [ "$status" -eq 0 ]
    run grep -F "$expected_suffix" <<< "$output"
    [ "$status" -eq 0 ]
  done
}

@test ".gitignore ignores local .cache directory" {
  run grep -E "^\.cache/" "$REPO_ROOT/.gitignore"
  [ "$status" -eq 0 ]
}

@test "mise.toml defines concurrent and serial molecule execution tasks" {
  local mise_config="$REPO_ROOT/mise.toml"
  [ -f "$mise_config" ]

  # Ensure concurrent test:ansible task exists and uses rush
  run yq eval '.tasks."test:ansible".run' "$mise_config"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "rush" ]]

  # Ensure sequential test:ansible:serial task exists and declares dependencies
  run yq eval '.tasks."test:ansible:serial".depends[]' "$mise_config"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test:ansible:base" ]]
  [[ "$output" =~ "test:ansible:restic" ]]
  [[ "$output" =~ "test:ansible:oci" ]]
  [[ "$output" =~ "test:ansible:homelab" ]]

  # Ensure test:ansible:fast runs converge and verify concurrently via rush
  run yq eval '.tasks."test:ansible:fast".run' "$mise_config"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "rush" ]]
  [[ "$output" =~ "molecule converge" ]]
  [[ "$output" =~ "molecule verify" ]]
}

