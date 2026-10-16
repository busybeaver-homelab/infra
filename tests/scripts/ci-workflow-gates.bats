#!/usr/bin/env bats
# Tests for Phase 3 CI workflow gates, SARIF verification, Harden Runner, and pre-push hooks (REV2-P3-1..3, REV2-P3-9, REV2-P3-10)

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
  CODEQL_YML="$REPO_ROOT/.github/workflows/codeql.yml"
  PRUNE_YML="$REPO_ROOT/.github/workflows/backup-prune.yml"
  DRIFT_YML="$REPO_ROOT/.github/workflows/drift-detection.yml"
  LEFTHOOK_YML="$REPO_ROOT/lefthook.yml"
}

@test "all workflows declare top-level permissions: {} and explicit timeout-minutes on every job (REV2-P3-9)" {
  for wf in "$CI_YML" "$CODEQL_YML" "$PRUNE_YML" "$DRIFT_YML"; do
    run yq eval '.permissions | keys | length' "$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    run yq eval '[.jobs[] | has("timeout-minutes")] | all' "$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "no workflow interpolates GitHub context expressions directly inside run: blocks (REV2-P3-9)" {
  for wf in "$CI_YML" "$CODEQL_YML" "$PRUNE_YML" "$DRIFT_YML"; do
    run yq eval '[.jobs[].steps[].run | select(. != null) | select(test("[$][{][{]"))] | length' "$wf"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
  done
}

@test "all secret-bearing and network-active workflow jobs include Harden Runner with egress-policy: audit (REV2-P3-9)" {
  for wf in "$CI_YML" "$CODEQL_YML" "$PRUNE_YML" "$DRIFT_YML"; do
    run grep -E "step-security/harden-runner@[0-9a-f]{40}" "$wf"
    [ "$status" -eq 0 ]
    run grep -F "egress-policy: audit" "$wf"
    [ "$status" -eq 0 ]
  done
}

@test "codeql.yml sets 30-minute timeout, uses uv run --locked, and verifies all 6 SARIF files (REV2-P3-2)" {
  run yq eval '.jobs.analyze-codeql.timeout-minutes' "$CODEQL_YML"
  [ "$status" -eq 0 ]
  [ "$output" = "30" ]

  run grep -n 'uvx ' "$CI_YML" "$CODEQL_YML" "$PRUNE_YML" "$DRIFT_YML"
  [ "$status" -ne 0 ]

  run yq eval '.jobs.analyze-iac-and-scripts.steps[] | select(.name == "Verify SARIF output files") | .run' "$CODEQL_YML"
  [ "$status" -eq 0 ]
  for sarif in checkov.sarif kics.sarif trivy-iac.sarif trivy-fs.sarif zizmor.sarif shellcheck.sarif; do
    [[ "$output" == *"$sarif"* ]] || false
  done
}

@test "lefthook.yml configures explicit --config for tflint and pre-push tofu-lint and tofu-validate (REV2-P3-3, REV2-P3-10)" {
  run yq eval '.pre-commit.commands.tofu-lint.run' "$LEFTHOOK_YML"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--config"* ]] || false
  [[ "$output" == *".tflint.hcl"* ]] || false

  run yq eval '.pre-push.commands.tofu-lint.run' "$LEFTHOOK_YML"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tflint --recursive --config"* ]] || false

  run yq eval '.pre-push.commands.tofu-validate.run' "$LEFTHOOK_YML"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tofu -chdir=\"\$d\" validate"* ]] || false
}
