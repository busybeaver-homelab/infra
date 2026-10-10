#!/usr/bin/env bats
# Tests for scripts/format-shellcheck-sarif.py

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/format-shellcheck-sarif.py"
  TEST_TMP="$BATS_TEST_TMPDIR"
}

@test "format-shellcheck-sarif.py exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "format-shellcheck-sarif.py passes ruff check and ruff format" {
  run uv run ruff check "$SCRIPT"
  [ "$status" -eq 0 ]

  run uv run ruff format --check "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "format-shellcheck-sarif: converts empty list to valid SARIF with 0 results" {
  run python3 "$SCRIPT" <<'EOF'
[]
EOF
  [ "$status" -eq 0 ]
  
  # Validate SARIF structure
  echo "$output" > "$TEST_TMP/output.sarif"
  run python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
assert data["version"] == "2.1.0"
assert len(data["runs"]) == 1
assert data["runs"][0]["tool"]["driver"]["name"] == "ShellCheck"
assert len(data["runs"][0]["results"]) == 0
' "$TEST_TMP/output.sarif"
  [ "$status" -eq 0 ]
}

@test "format-shellcheck-sarif: converts shellcheck JSON findings to valid SARIF" {
  run python3 "$SCRIPT" <<'EOF'
[
  {
    "file": "scripts/test.sh",
    "line": 10,
    "endLine": 10,
    "column": 5,
    "endColumn": 15,
    "level": "error",
    "code": 2086,
    "message": "Double quote to prevent globbing and word splitting."
  },
  {
    "file": "scripts/test.sh",
    "line": 15,
    "endLine": 15,
    "column": 1,
    "endColumn": 5,
    "level": "warning",
    "code": 2034,
    "message": "foo appears unused. Verify use."
  },
  {
    "file": "scripts/test.sh",
    "line": 20,
    "endLine": 20,
    "column": 1,
    "endColumn": 8,
    "level": "info",
    "code": 2154,
    "message": "bar is referenced but not assigned."
  }
]
EOF
  [ "$status" -eq 0 ]

  echo "$output" > "$TEST_TMP/findings.sarif"
  run python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
run = data["runs"][0]
assert run["tool"]["driver"]["name"] == "ShellCheck"
results = run["results"]
assert len(results) == 3

# Check result 0 (error -> error)
assert results[0]["ruleId"] == "SC2086"
assert results[0]["level"] == "error"
assert results[0]["locations"][0]["physicalLocation"]["artifactLocation"]["uri"] == "scripts/test.sh"
assert results[0]["locations"][0]["physicalLocation"]["region"]["startLine"] == 10

# Check result 1 (warning -> warning)
assert results[1]["ruleId"] == "SC2034"
assert results[1]["level"] == "warning"

# Check result 2 (info -> note)
assert results[2]["ruleId"] == "SC2154"
assert results[2]["level"] == "note"

# Check rules defined
rules = run["tool"]["driver"]["rules"]
rule_ids = {r["id"] for r in rules}
assert rule_ids == {"SC2086", "SC2034", "SC2154"}
' "$TEST_TMP/findings.sarif"
  [ "$status" -eq 0 ]
}

@test "format-shellcheck-sarif: handles empty input gracefully" {
  run python3 "$SCRIPT" <<'EOF'
EOF
  [ "$status" -eq 0 ]
  echo "$output" > "$TEST_TMP/empty.sarif"
  run python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
assert len(data["runs"][0]["results"]) == 0
' "$TEST_TMP/empty.sarif"
  [ "$status" -eq 0 ]
}
