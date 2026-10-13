#!/usr/bin/env bats
# Tests for mise lock sidecars and uv toolchain configuration

load 'helpers/test_helper'

@test "mise.toml specifies uv in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E 'uv\s*=\s*"0\.13"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test ".gitignore explicitly unignores .mise/locks/" {
  local gitignore="${REPO_ROOT}/.gitignore"
  [ -f "$gitignore" ]
  run grep -E '^\!\.mise/locks/' "$gitignore"
  [ "$status" -eq 0 ]
}

@test ".gitignore ignores .mise/* except locks" {
  local gitignore="${REPO_ROOT}/.gitignore"
  [ -f "$gitignore" ]
  run grep -E '^\.mise/\*' "$gitignore"
  [ "$status" -eq 0 ]
}

@test "git check-ignore ignores .mise/cache and .mise/installs" {
  cd "$REPO_ROOT"
  run git check-ignore -q .mise/cache
  [ "$status" -eq 0 ]

  run git check-ignore -q .mise/installs
  [ "$status" -eq 0 ]
}

@test "git check-ignore does not ignore .mise/locks files" {
  cd "$REPO_ROOT"
  run git check-ignore -q .mise/locks/oxfmt/0.71.0/package.json
  [ "$status" -eq 1 ]

  run git check-ignore -q .mise/locks/oxfmt/0.71.0/aube-lock.yaml
  [ "$status" -eq 1 ]
}

@test "lock sidecar files exist for oxfmt and ansible sidecar is removed" {
  [ -f "${REPO_ROOT}/.mise/locks/oxfmt/0.71.0/package.json" ]
  [ -f "${REPO_ROOT}/.mise/locks/oxfmt/0.71.0/aube-lock.yaml" ]
  [ ! -d "${REPO_ROOT}/.mise/locks/ansible" ]
}

@test "mise.toml does not configure ansible in [tools]" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^ansible\s*=' "$mise_config"
  [ "$status" -ne 0 ]
}

@test "mise.toml configures min_version and lockfile_platforms" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^min_version\s*=\s*"2026\.10\.8"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'lockfile_platforms\s*=\s*\["macos-arm64",\s*"linux-x64"\]' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "setup-environment composite action pins matching Mise CLI version" {
  local action_file="${REPO_ROOT}/.github/actions/setup-environment/action.yml"
  [ -f "$action_file" ]
  run grep -E 'version:\s*"2026\.10\.8"' "$action_file"
  [ "$status" -eq 0 ]
}

@test "mise.lock references oxfmt sidecar and does not reference ansible" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\.mise/locks/oxfmt/0\.71\.0' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -i 'ansible' "$mise_lock"
  [ "$status" -ne 0 ]
}

@test "mise.lock oxfmt aube digest matches CI Linux digest" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E 'digest = "sha256:98e4ad5fda0b7ae3ae05abd1809e4764bc290c131db8df6fe4f66d9f0252f913"' "$mise_lock"
  [ "$status" -eq 0 ]
}

@test "lefthook.yml defines mise-lock-check hook" {
  local lefthook_config="${REPO_ROOT}/lefthook.yml"
  [ -f "$lefthook_config" ]
  run grep -E 'mise-lock-check:' "$lefthook_config"
  [ "$status" -eq 0 ]
  run grep -E 'run:\s*mise lock --dry-run' "$lefthook_config"
  [ "$status" -eq 0 ]
}

@test ".python-version file does not exist in repository" {
  [ ! -f "${REPO_ROOT}/.python-version" ]
}

@test "pyproject.toml requires-python specifies compatible range matching mise.toml" {
  local pyproject="${REPO_ROOT}/pyproject.toml"
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$pyproject" ]
  [ -f "$mise_config" ]

  # Must use compatible range (~=3.14.0), not strict patch pin (==)
  run grep -E '^requires-python\s*=\s*"~=3\.14\.0"' "$pyproject"
  [ "$status" -eq 0 ]

  # Must NOT use exact equality pin
  run grep -E '^requires-python\s*=\s*"==.*"' "$pyproject"
  [ "$status" -ne 0 ]
}

@test "mise.toml specifies gh in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^gh\s*=\s*"2\.102"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.lock contains gh tool entry with aqua backend" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\[\[tools\.gh\]\]' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "aqua:cli/cli"' "$mise_lock"
  [ "$status" -eq 0 ]
}

@test "gh cli executes cleanly via mise and outputs expected version" {
  run mise exec -- gh --version
  [ "$status" -eq 0 ]
  run grep -E '^gh version 2\.102\.' <<< "$output"
  [ "$status" -eq 0 ]
}

