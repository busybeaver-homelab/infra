#!/usr/bin/env bats
# Tests for .github/workflows/codeql.yml

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/codeql.yml"
}

@test "codeql.yml exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
assert "jobs" in data
assert "name" in data
' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "codeql.yml passes actionlint" {
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "codeql.yml defines expected triggers and permissions" {
  run python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))

# Triggers
on = data.get("on") or data.get(True)
assert "push" in on
assert "pull_request" in on
assert "schedule" in on
assert "workflow_dispatch" in on

# Permissions
perms = data.get("permissions", {})
assert perms.get("contents") == "read"
assert perms.get("security-events") == "write"
assert perms.get("actions") == "read"
' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "codeql.yml defines analyze-codeql matrix for actions and python" {
  run python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
jobs = data.get("jobs", {})
assert "analyze-codeql" in jobs
matrix = jobs["analyze-codeql"].get("strategy", {}).get("matrix", {})
assert set(matrix.get("language", [])) == {"actions", "python"}
' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "codeql.yml defines analyze-iac-and-scripts with Trivy and ShellCheck uploads" {
  run python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
jobs = data.get("jobs", {})
assert "analyze-iac-and-scripts" in jobs
steps = jobs["analyze-iac-and-scripts"].get("steps", [])

# Verify steps run Trivy and ShellCheck and upload SARIF
categories = []
for s in steps:
    with_block = s.get("with", {})
    cat = with_block.get("category")
    if cat:
        categories.append(cat)

assert "trivy-iac" in categories
assert "shellcheck" in categories
' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "codeql.yml pins all external action uses to 40-character commit SHAs" {
  local invalid_pins=0
  while IFS= read -r line; do
    local target
    target="$(echo "$line" | sed -E 's/^[0-9]+:[[:space:]]*uses:[[:space:]]*//' | sed -E 's/[[:space:]]*#.*$//')"
    if [[ "$target" =~ ^\./ ]]; then
      continue
    fi
    if [[ ! "$target" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(/[^@]+)?@[a-f0-9]{40}$ ]]; then
      echo "Unpinned action in codeql.yml: $target" >&2
      invalid_pins=$((invalid_pins + 1))
    fi
  done < <(grep -nE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$WORKFLOW")

  [ "$invalid_pins" -eq 0 ]
}
