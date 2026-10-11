#!/usr/bin/env bats
# Tests for .github/workflows/ci.yml and .github/actions/setup-environment

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
  ACTION="$REPO_ROOT/.github/actions/setup-environment/action.yml"
}

@test "setup-environment composite action file exists and is valid YAML" {
  [ -f "$ACTION" ]
  run yq eval '.' "$ACTION"
  [ "$status" -eq 0 ]
}

@test "setup-environment composite action defines inputs with default false" {
  run yq eval '.inputs.python.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run yq eval '.inputs.tflint.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run yq eval '.inputs.galaxy.default' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "setup-environment composite action installs mise with cache true" {
  run yq eval '.runs.steps[] | select(.uses == "*jdx/mise-action*") | .with.cache' "$ACTION"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ci.yml exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run yq eval '.' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml does not contain deprecated build-apps job" {
  run yq eval '.jobs.build-apps' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "ci.yml uses setup-environment composite action" {
  run grep -E "uses: \./\.github/actions/setup-environment" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "ci.yml ci-gate does not depend on build-apps" {
  run yq eval '.jobs.ci-gate.needs[] | select(. == "build-apps")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "apps/sample-app is pruned and apps/README.md documents architecture boundary" {
  [ ! -d "$REPO_ROOT/apps/sample-app" ]
  [ -f "$REPO_ROOT/apps/README.md" ]

  run grep -E "Docker Compose Stacks" "$REPO_ROOT/apps/README.md"
  [ "$status" -eq 0 ]

  run grep -E "Cloudflare Workers" "$REPO_ROOT/apps/README.md"
  [ "$status" -eq 0 ]
}

@test "mise check:general task runs cleanly with --no-error-on-unmatched-pattern" {
  run mise run check:general
  [ "$status" -eq 0 ]
}

@test "ci.yml does not contain redundant security-scan job" {
  run yq eval '.jobs.security-scan' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
@test "ci.yml ci-gate does not depend on security-scan" {
  run yq eval '.jobs.ci-gate.needs[] | select(. == "security-scan")' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mise tasks include granular and aggregate security scanning tasks" {
  run mise tasks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "check:security" ]] || false
  [[ "$output" =~ "check:security:checkov" ]] || false
  [[ "$output" =~ "check:security:kics" ]] || false
  [[ "$output" =~ "check:security:trivy" ]] || false
}

@test "codeql.yml defines multi-engine security scanning with distinct categories" {
  run yq eval '.jobs.analyze-iac-and-scripts.steps[] | select(.uses == "*upload-sarif*") | .with.category' "$REPO_ROOT/.github/workflows/codeql.yml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "checkov" ]] || false
  [[ "$output" =~ "kics" ]] || false
  [[ "$output" =~ "trivy-iac" ]] || false
  [[ "$output" =~ "trivy-fs" ]] || false
  [[ "$output" =~ "zizmor" ]] || false
  [[ "$output" =~ "shellcheck" ]] || false
}

@test "ci.yml shell-bats job sets python and galaxy true in setup-environment" {
  run yq eval '.jobs.shell-bats.steps[] | select(.uses == "./.github/actions/setup-environment") | .with.python' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.shell-bats.steps[] | select(.uses == "./.github/actions/setup-environment") | .with.galaxy' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ci.yml lint-format job sets python, galaxy, and tflint true in setup-environment" {
  run yq eval '.jobs.lint-format.steps[] | select(.uses == "./.github/actions/setup-environment") | .with.python' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.lint-format.steps[] | select(.uses == "./.github/actions/setup-environment") | .with.galaxy' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq eval '.jobs.lint-format.steps[] | select(.uses == "./.github/actions/setup-environment") | .with.tflint' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

