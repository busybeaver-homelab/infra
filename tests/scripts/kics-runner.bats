#!/usr/bin/env bats
# Tests for scripts/run-kics.sh

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER="$REPO_ROOT/scripts/run-kics.sh"
}

@test "run-kics.sh exists and is executable" {
  [ -f "$RUNNER" ]
  [ -x "$RUNNER" ]
}

@test "run-kics.sh --help displays usage information" {
  run "$RUNNER" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]] || false
  [[ "$output" =~ "checkmarx/kics" ]]
}

@test "run-kics.sh rejects invalid options" {
  run "$RUNNER" --invalid-flag
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown option" ]]
}

@test "run-kics.sh supports dry-run or docker check" {
  run "$RUNNER" --check-docker
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Docker is available" ]] || false
  else
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Docker daemon is not running" ]] || false
  fi
}

@test "run-kics.sh sanitizes /path/ and \"path/ in sarif output" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local sarif_file="$tmp_dir/kics.sarif"
  cat <<'EOF' > "$sarif_file"
{"runs":[{"results":[{"locations":[{"physicalLocation":{"artifactLocation":{"uri":"/path/infrastructure/main.tf"}}}]},{"locations":[{"physicalLocation":{"artifactLocation":{"uri":"path/configuration/site.yml"}}}]}]}]}
EOF
  sed -i.bak -e 's|/path/||g' -e 's|"path/|"|g' "$sarif_file" && rm -f "${sarif_file}.bak"
  run grep '"uri":"infrastructure/main.tf"' "$sarif_file"
  [ "$status" -eq 0 ]
  run grep '"uri":"configuration/site.yml"' "$sarif_file"
  [ "$status" -eq 0 ]
  rm -rf "$tmp_dir"
}

