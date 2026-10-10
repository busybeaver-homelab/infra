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

  run git check-ignore -q .mise/locks/ansible/14.4.0~0672620e/uv.lock
  [ "$status" -eq 1 ]
}

@test "lock sidecar files exist for oxfmt and ansible" {
  [ -f "${REPO_ROOT}/.mise/locks/oxfmt/0.71.0/package.json" ]
  [ -f "${REPO_ROOT}/.mise/locks/oxfmt/0.71.0/aube-lock.yaml" ]
  [ -f "${REPO_ROOT}/.mise/locks/ansible/14.4.0~0672620e/uv.lock" ]
  [ -f "${REPO_ROOT}/.mise/locks/ansible/14.4.0~0672620e/pyproject.toml" ]
}

@test "mise.lock references the sidecar lock files" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\.mise/locks/oxfmt/0\.71\.0' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E '\.mise/locks/ansible/14\.4\.0~0672620e' "$mise_lock"
  [ "$status" -eq 0 ]
}

@test "mise.lock oxfmt aube digest matches CI Linux digest" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E 'digest = "sha256:98e4ad5fda0b7ae3ae05abd1809e4764bc290c131db8df6fe4f66d9f0252f913"' "$mise_lock"
  [ "$status" -eq 0 ]
}
