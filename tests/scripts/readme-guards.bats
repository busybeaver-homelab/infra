#!/usr/bin/env bats
# Tests for README.md structure, Mermaid diagram syntax, and content guards

load 'helpers/test_helper'

setup() {
  setup_tmpdir
}

teardown() {
  teardown_tmpdir
}

@test "README.md exists and contains high-level architecture mermaid block" {
  local readme="${REPO_ROOT}/README.md"
  [ -f "$readme" ]
  run grep -F '```mermaid' "$readme"
  [ "$status" -eq 0 ]
}

@test "README.md mermaid diagram does not contain unquoted parentheses in edge labels" {
  local readme="${REPO_ROOT}/README.md"
  local mmd_file="${BATS_TMPDIR}/diagram.mmd"
  awk '/```mermaid/{flag=1; next} /```/{flag=0} flag' "$readme" >"$mmd_file"

  # Grep for unquoted parentheses inside edge labels (|...(...)...|)
  run grep -E '\|[^"|]*\([^"|]*\|' "$mmd_file"
  [ "$status" -ne 0 ]
}

@test "README.md mermaid diagram edge labels with parentheses are properly quoted" {
  local readme="${REPO_ROOT}/README.md"
  run grep -F '|"Encrypted State (AES-GCM)"|' "$readme"
  [ "$status" -eq 0 ]
}

@test "README.md mermaid diagram includes all cloud, SaaS, and homelab nodes and key flows" {
  local readme="${REPO_ROOT}/README.md"
  local mmd_file="${BATS_TMPDIR}/diagram.mmd"
  awk '/```mermaid/{flag=1; next} /```/{flag=0} flag' "$readme" >"$mmd_file"

  for token in "CF[" "OCI[" "GCP[" "Azure[" "Mesh[" "DNS[" "Mon[" "GH[" "UniFi[" "Ubuntu["; do
    run grep -F "$token" "$mmd_file"
    [ "$status" -eq 0 ]
  done

  run grep -E 'Ans ===>.*GCP' "$mmd_file"
  [ "$status" -eq 0 ]

  run grep -F 'Dual-Target Restic Backups' "$mmd_file"
  [ "$status" -eq 0 ]
}

@test "README.md mermaid diagram compiles successfully with mmdc if available" {
  if ! command -v mmdc &>/dev/null; then
    skip "mmdc is not installed in the current environment"
  fi

  local readme="${REPO_ROOT}/README.md"
  local mmd_file="${BATS_TMPDIR}/diagram.mmd"
  local svg_file="${BATS_TMPDIR}/diagram.svg"

  awk '/```mermaid/{flag=1; next} /```/{flag=0} flag' "$readme" >"$mmd_file"
  run mmdc -i "$mmd_file" -o "$svg_file"
  [ "$status" -eq 0 ]
  [ -s "$svg_file" ]
}

@test "README.md documents all 9 OpenTofu root modules and directory layout entries" {
  local readme="${REPO_ROOT}/README.md"

  for mod in azure cloudflare dns gcp github homelab mesh monitoring oci; do
    run grep -F "[\`${mod}\`](infrastructure/${mod}/)" "$readme"
    [ "$status" -eq 0 ]
    run grep -E "├── ${mod}/|└── ${mod}/" "$readme"
    [ "$status" -eq 0 ]
  done

  for entry in "group_vars/" "molecule/" "modules/" "tests/" "scripts/"; do
    run grep -F "$entry" "$readme"
    [ "$status" -eq 0 ]
  done
}

@test "README.md documents current mise.toml and pyproject.toml toolset and tasks" {
  local readme="${REPO_ROOT}/README.md"

  # Must reference mise.toml rather than legacy .mise.toml
  run grep -F ".mise.toml" "$readme"
  [ "$status" -ne 0 ]

  for tool_pattern in \
    '\*\*uv\*\*.*`0\.13`' \
    '\*\*Restic\*\*.*`0\.18`' \
    '\*\*Rush\*\*.*`0\.11\.0`' \
    '\*\*GitHub CLI \(`gh`\)\*\*.*`2\.102`' \
    '\*\*Ansible-Lint\*\*.*`26\.10\.1`' \
    '\*\*Molecule\*\*.*`26\.10\.0`'; do
    run grep -E "$tool_pattern" "$readme"
    [ "$status" -eq 0 ]
  done

  for task_cmd in "mise run test:all" "mise run check:security" "mise run state:snapshot" "mise run drift:all"; do
    run grep -F "$task_cmd" "$readme"
    [ "$status" -eq 0 ]
  done
}

@test "README.md does not contain contributing guidelines section" {
  local readme="${REPO_ROOT}/README.md"
  run grep -i -E '^#+\s*.*contribut' "$readme"
  [ "$status" -ne 0 ]

  run grep -i "Contributing Guidelines" "$readme"
  [ "$status" -ne 0 ]
}
