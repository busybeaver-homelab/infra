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

@test "ci.yml security-scan job runs trivy via mise toolchain and outputs sarif" {
  run grep -E "mise exec -- trivy fs --format sarif" "$WORKFLOW"
  [ "$status" -eq 0 ]
}
