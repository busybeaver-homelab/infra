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
  awk '/```mermaid/{flag=1; next} /```/{flag=0} flag' "$readme" > "$mmd_file"

  # Grep for unquoted parentheses inside edge labels (|...(...)...|)
  run grep -E '\|[^"|]*\([^"|]*\|' "$mmd_file"
  [ "$status" -ne 0 ]
}

@test "README.md mermaid diagram edge labels with parentheses are properly quoted" {
  local readme="${REPO_ROOT}/README.md"
  run grep -F '|"Encrypted State (AES-GCM)"|' "$readme"
  [ "$status" -eq 0 ]
}

@test "README.md mermaid diagram compiles successfully with mmdc if available" {
  if ! command -v mmdc &>/dev/null; then
    skip "mmdc is not installed in the current environment"
  fi

  local readme="${REPO_ROOT}/README.md"
  local mmd_file="${BATS_TMPDIR}/diagram.mmd"
  local svg_file="${BATS_TMPDIR}/diagram.svg"

  awk '/```mermaid/{flag=1; next} /```/{flag=0} flag' "$readme" > "$mmd_file"
  run mmdc -i "$mmd_file" -o "$svg_file"
  [ "$status" -eq 0 ]
  [ -s "$svg_file" ]
}

@test "README.md does not contain contributing guidelines section" {
  local readme="${REPO_ROOT}/README.md"
  run grep -i -E '^#+\s*.*contribut' "$readme"
  [ "$status" -ne 0 ]

  run grep -i "Contributing Guidelines" "$readme"
  [ "$status" -ne 0 ]
}
