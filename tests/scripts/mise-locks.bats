#!/usr/bin/env bats
# Tests for mise lock sidecars and uv toolchain configuration

load 'helpers/test_helper'

@test "mise.toml specifies aqua:astral-sh/uv in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '"aqua:astral-sh/uv"\s*=\s*"0\.13"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.lock contains aqua:astral-sh/uv tool entries and no legacy asdf:uv backend" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\[\[tools\."aqua:astral-sh/uv"\]\]' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "aqua:astral-sh/uv"' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "asdf:uv"' "$mise_lock"
  [ "$status" -ne 0 ]
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

@test "legacy npm/pipx lock sidecars for oxfmt and ansible are removed" {
  [ ! -d "${REPO_ROOT}/.mise/locks/oxfmt" ]
  [ ! -d "${REPO_ROOT}/.mise/locks/ansible" ]
}

@test "mise.toml does not configure ansible in [tools]" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^ansible\s*=' "$mise_config"
  [ "$status" -ne 0 ]
}

@test "mise.toml configures min_version, lockfile_platforms, and disable_backends" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^min_version\s*=\s*"2026\.10\.8"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E 'lockfile_platforms\s*=\s*\["macos-arm64",\s*"linux-x64"\]' "$mise_config"
  [ "$status" -eq 0 ]
  run yq -p toml -oy '.settings.disable_backends' "$mise_config"
  [ "$status" -eq 0 ]
  for backend in asdf vfox cargo dotnet gem go npm pipx spm; do
    grep -Fq "$backend" <<<"$output"
  done
  run yq -p toml -oy '.settings.aqua.baked_registry' "$mise_config"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "setup-environment composite action pins matching Mise CLI version" {
  local action_file="${REPO_ROOT}/.github/actions/setup-environment/action.yml"
  [ -f "$action_file" ]
  run grep -E 'version:\s*"2026\.10\.8"' "$action_file"
  [ "$status" -eq 0 ]
}

@test "mise.toml and mise.lock use aqua:oxc-project/oxc/oxfmt without npm/aube sidecars or ansible" {
  local mise_config="${REPO_ROOT}/mise.toml"
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_config" ]
  [ -f "$mise_lock" ]
  run grep -E '^"aqua:oxc-project/oxc/oxfmt"\s*=\s*"0\.73"' "$mise_config"
  [ "$status" -eq 0 ]
  run grep -E '\[\[tools\."aqua:oxc-project/oxc/oxfmt"\]\]' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "aqua:oxc-project/oxc/oxfmt"' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'npm:oxfmt|\.mise/locks/oxfmt' "$mise_lock"
  [ "$status" -ne 0 ]
  run grep -i 'ansible' "$mise_lock"
  [ "$status" -ne 0 ]
}

@test "every tool in mise.toml [tools] is explicitly prefixed with aqua: or core: and locked in mise.lock" {
  local mise_config="${REPO_ROOT}/mise.toml"
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_config" ]
  [ -f "$mise_lock" ]

  local keys
  keys="$(yq -p toml -oy '.tools | keys' "$mise_config" | sed -nE 's/^- "?([^"]+)"?$/\1/p')"
  [ -n "$keys" ]

  local count=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    count=$((count + 1))
    if [[ ! "$key" =~ ^(aqua:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?|core:(python|go|node))$ ]]; then
      echo "Tool key '$key' in mise.toml is not explicitly prefixed with aqua: or core:" >&2
      return 1
    fi
    local lock_header
    if [[ "$key" == core:* ]]; then
      lock_header="[[tools.${key#core:}]]"
    else
      lock_header="[[tools.\"${key}\"]]"
    fi
    if ! grep -Fq "$lock_header" "$mise_lock"; then
      echo "Missing ${lock_header} entry in mise.lock" >&2
      return 1
    fi
    if ! grep -Fq "backend = \"${key}\"" "$mise_lock"; then
      echo "Missing backend = \"${key}\" entry in mise.lock" >&2
      return 1
    fi
  done <<<"$keys"

  [ "$count" -ge 22 ]

  # Ensure no unprefixed [[tools.<bare>]] headers remain in mise.lock other than core runtimes (go, node, python)
  run grep -E '^\[\[tools\.[a-z0-9_-]+\]\]$' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -Ev '^\[\[tools\.(go|node|python)\]\]$' <<<"$output"
  [ "$status" -ne 0 ]
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

@test "mise.toml specifies aqua:cli/cli (gh) in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '^"aqua:cli/cli"\s*=\s*"2\.102"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.lock contains aqua:cli/cli tool entry with aqua backend" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\[\[tools\."aqua:cli/cli"\]\]' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "aqua:cli/cli"' "$mise_lock"
  [ "$status" -eq 0 ]
}

@test "gh cli executes cleanly via mise and outputs expected version" {
  run mise exec -- gh --version
  [ "$status" -eq 0 ]
  run grep -E '^gh version 2\.102\.' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "mise.toml specifies aqua:shenwei356/rush in toolchain" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]
  run grep -E '"aqua:shenwei356/rush"\s*=\s*"0\.11\.0"' "$mise_config"
  [ "$status" -eq 0 ]
}

@test "mise.lock contains aqua:shenwei356/rush tool entries with aqua backend" {
  local mise_lock="${REPO_ROOT}/mise.lock"
  [ -f "$mise_lock" ]
  run grep -E '\[\[tools\."aqua:shenwei356/rush"\]\]' "$mise_lock"
  [ "$status" -eq 0 ]
  run grep -E 'backend = "aqua:shenwei356/rush"' "$mise_lock"
  [ "$status" -eq 0 ]
}

@test "rush parallel runner executes cleanly via mise and outputs expected version" {
  run mise exec -- rush --version
  [ "$status" -eq 0 ]
  run grep -E '^rush v0\.11\.0' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "every aqua: tool in mise.toml specifies at least major.minor version (including trufflehog and yq)" {
  local mise_config="${REPO_ROOT}/mise.toml"
  [ -f "$mise_config" ]

  run grep -E '^"aqua:trufflesecurity/trufflehog"\s*=\s*"3\.97"' "$mise_config"
  [ "$status" -eq 0 ]

  run grep -E '^"aqua:mikefarah/yq"\s*=\s*"4\.54"' "$mise_config"
  [ "$status" -eq 0 ]

  local entries
  entries="$(yq -p toml -oy '.tools | to_entries | .[] | select(.key | test("^aqua:")) | .key + "=" + .value' "$mise_config")"
  [ -n "$entries" ]

  while IFS='=' read -r key ver; do
    [ -n "$key" ] || continue
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      echo "Aqua tool '$key' has major-only or invalid version specifier '$ver' in mise.toml (expected major.minor or major.minor.patch)" >&2
      return 1
    fi
  done <<<"$entries"
}
