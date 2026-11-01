#!/usr/bin/env bats
# Tests for .github/workflows/workflow-policy.yml (design 4.7)

load 'helpers/test_helper'

setup() {
  WORKFLOW="${REPO_ROOT}/.github/workflows/workflow-policy.yml"
  CI_WORKFLOW="${REPO_ROOT}/.github/workflows/ci.yml"
}

@test "workflow-policy.yml exists and passes actionlint" {
  [ -f "$WORKFLOW" ]
  run actionlint "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "workflow and its single job are named Workflow Policy (required check name)" {
  run yq -r '.name' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "Workflow Policy" ]

  run yq -r '.jobs | length' "$WORKFLOW"
  [ "$output" = "1" ]
  run yq -r '.jobs[].name' "$WORKFLOW"
  [ "$output" = "Workflow Policy" ]
}

@test "workflow triggers on pull_request, merge_group and push to main" {
  run yq -o=json -I=0 '.on | keys | sort' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = '["merge_group","pull_request","push"]' ]
  run yq -r '.on.push.branches[]' "$WORKFLOW"
  [ "$output" = "main" ]
  run yq -r '.on.merge_group.types[]' "$WORKFLOW"
  [ "$output" = "checks_requested" ]
  run yq -r '.on.merge_group.branches[]' "$WORKFLOW"
  [ "$output" = "main" ]
}

@test "pull_request branch list and types match ci.yml" {
  run yq -o=json -I=0 '.on.pull_request' "$CI_WORKFLOW"
  local expected="$output"
  run yq -o=json -I=0 '.on.pull_request' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "required check always reports: no job condition and no path filters" {
  run yq -r '.jobs[] | has("if")' "$WORKFLOW"
  [ "$output" = "false" ]
  run yq -r '.on | to_entries | .[] | .value | select(. != null) | select(has("paths") or has("paths-ignore"))' "$WORKFLOW"
  [ -z "$output" ]
}

@test "workflow uses least privilege and declares no environment anywhere" {
  run yq -o=json -I=0 '.permissions' "$WORKFLOW"
  [ "$output" = '{"contents":"read"}' ]
  run yq -r '.jobs[] | has("permissions")' "$WORKFLOW"
  [ "$output" = "false" ]

  run yq -r '[.. | select(tag == "!!map") | select(has("environment"))] | length' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  run grep -E '^[[:space:]]*environment:' "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "workflow has timeout, concurrency, and Harden Runner as the first step" {
  run yq -r '.jobs[].timeout-minutes' "$WORKFLOW"
  [[ "$output" =~ ^[0-9]+$ ]] || false
  run yq -r '.concurrency.group' "$WORKFLOW"
  [[ "$output" == *'github.workflow'* ]] || false
  run yq -r '.jobs[].steps[0].uses' "$WORKFLOW"
  [[ "$output" =~ ^step-security/harden-runner@[0-9a-f]{40}$ ]] || false
  run yq -r '.jobs[].steps[0].with."egress-policy"' "$WORKFLOW"
  [ "$output" = "audit" ]
}

@test "all uses: entries are SHA-pinned or the local setup composite" {
  local line target count=0
  while IFS= read -r line; do
    target="$(sed -E 's/^[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]*#.*$//' <<<"$line")"
    count=$((count + 1))
    if [[ "$target" =~ ^(\./|\$/)\.?github/actions/setup-environment$ ]]; then
      continue
    fi
    [[ "$target" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+(/[^@]+)?@[a-f0-9]{40}$ ]] || {
      echo "unpinned: $line" >&2
      return 1
    }
  done < <(grep -E '^[[:space:]]*uses:' "$WORKFLOW")
  [ "$count" -ge 3 ]
}

@test "checkout does not persist credentials and the job runs the policy script via mise" {
  run yq -r '.jobs[].steps[] | select(.uses | test("^actions/checkout@")) | .with."persist-credentials"' "$WORKFLOW"
  [ "$output" = "false" ]
  run yq -r '.jobs[].steps[] | select(.run != null) | .run' "$WORKFLOW"
  [[ "$output" == *"mise exec -- "*"scripts/check-workflow-environments.sh"* ]] || false
}

@test "no run: block interpolates GitHub expressions" {
  run yq -r '[.jobs[].steps[].run | select(. != null) | select(test("[$][{][{]"))] | length' "$WORKFLOW"
  [ "$output" = "0" ]
}
