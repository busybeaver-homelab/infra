#!/usr/bin/env bats
# Tests for .github/workflows/codeql.yml

load 'helpers/test_helper'

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

# Top-level permissions must be empty {} (REV2-P3-9)
perms = data.get("permissions")
assert perms == {}, f"expected top-level permissions {{}}, got {perms}"

# Job-level permissions
for job_name in ("analyze-codeql", "analyze-iac-and-scripts"):
    jperms = data["jobs"][job_name].get("permissions", {})
    assert jperms.get("contents") == "read"
    assert jperms.get("security-events") == "write"
    assert jperms.get("actions") == "read"
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
    if [[ "$target" =~ ^(\./|\$/) ]]; then
      continue
    fi
    if [[ ! "$target" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(/[^@]+)?@[a-f0-9]{40}$ ]]; then
      echo "Unpinned action in codeql.yml: $target" >&2
      invalid_pins=$((invalid_pins + 1))
    fi
  done < <(grep -nE '^[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$WORKFLOW")

  [ "$invalid_pins" -eq 0 ]
}

@test "codeql.yml binds analyze-codeql and analyze-iac-and-scripts jobs to code_quality environment" {
  run yq eval '.jobs.analyze-codeql.environment' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "code_quality" ]

  run yq eval '.jobs.analyze-iac-and-scripts.environment' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "code_quality" ]
}

@test "codeql.yml filters inline-suppressed Checkov findings from SARIF before upload" {
  run yq eval '.jobs.analyze-iac-and-scripts.steps[] | select(.name == "Run Checkov IaC & Configuration Scanner") | .run' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ".suppressions" ]] || false
  [[ "$output" =~ "results_sarif.sarif" ]]
}

@test "codeql.yml pull_request triggers on main and stacked PR base branch patterns (STD-CI-02, STD-CI-73)" {
  run yq '.on.pull_request.types | join(",")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"opened"* ]] || false
  [[ "$output" == *"edited"* ]] || false
  [[ "$output" == *"synchronize"* ]] || false
  [[ "$output" == *"reopened"* ]] || false

  local pattern
  for pattern in main "feat/**" "fix/**" "chore/**" "docs/**" "refactor/**" "test/**" "ci/**" "perf/**" "style/**" "build/**"; do
    run yq ".on.pull_request.branches[] | select(. == \"${pattern}\")" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "$pattern" ]
  done
}

# Prints each code-scanning configuration under <root>/.github/workflows as
# "<workflow file>|<job id>|<category>", one per SARIF upload or CodeQL analyze step.
sarif_configs() {
  python3 - "$1" <<'PY'
import glob, os, sys, yaml
rows = set()
for path in glob.glob(os.path.join(sys.argv[1], ".github/workflows/*.y*ml")):
    data = yaml.safe_load(open(path)) or {}
    for job_id, job in (data.get("jobs") or {}).items():
        for step in job.get("steps") or []:
            uses = step.get("uses") or ""
            if "codeql-action/upload-sarif" in uses or "codeql-action/analyze" in uses:
                category = (step.get("with") or {}).get("category", "")
                rows.add(f"{os.path.basename(path)}|{job_id}|{category}")
print("\n".join(sorted(rows)))
PY
}

# Changing this list means a configuration on main is retired: delete it there
# (STD-CI-74), or the required code-scanning rule blocks every PR.
EXPECTED_SARIF_CONFIGS='codeql.yml|analyze-codeql|/language:${{ matrix.language }}
codeql.yml|analyze-iac-and-scripts|checkov
codeql.yml|analyze-iac-and-scripts|kics
codeql.yml|analyze-iac-and-scripts|shellcheck
codeql.yml|analyze-iac-and-scripts|trivy-fs
codeql.yml|analyze-iac-and-scripts|trivy-iac
codeql.yml|analyze-iac-and-scripts|zizmor'

@test "SARIF configurations match the reviewed set (STD-CI-74)" {
  run sarif_configs "$REPO_ROOT"
  [ "$status" -eq 0 ]
  if [ "$output" != "$EXPECTED_SARIF_CONFIGS" ]; then
    echo "SARIF configurations changed. Delete the retired configuration on refs/heads/main (STD-CI-74), then update EXPECTED_SARIF_CONFIGS."
    diff <(echo "$EXPECTED_SARIF_CONFIGS") <(echo "$output") || true
    false
  fi
}

@test "a renamed SARIF category or moved upload job changes the configuration set (STD-CI-74)" {
  local root="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${root}/.github/workflows"
  sed 's/category: trivy-fs/category: trivy-filesystem/' "$WORKFLOW" > "${root}/.github/workflows/codeql.yml"
  run sarif_configs "$root"
  [ "$status" -eq 0 ]
  [ "$output" != "$EXPECTED_SARIF_CONFIGS" ]
  [[ "$output" == *"codeql.yml|analyze-iac-and-scripts|trivy-filesystem"* ]] || false
  [[ "$output" != *"|trivy-fs"* ]] || false

  sed 's/^  analyze-iac-and-scripts:/  security-scan:/' "$WORKFLOW" > "${root}/.github/workflows/codeql.yml"
  run sarif_configs "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codeql.yml|security-scan|trivy-fs"* ]]
}
