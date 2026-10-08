#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/drift-detection.yml"
}

@test "drift detection workflow file exists and is valid YAML" {
  [ -f "$WORKFLOW" ]
  run yq eval '.' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow defines daily schedule and workflow_dispatch triggers" {
  run yq eval '.on.schedule[0].cron' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" = "0 6 * * *" ]

  run yq eval '.on.workflow_dispatch' "$WORKFLOW"
  [ "$status" -eq 0 ]
  [ "$output" != "null" ]
}

@test "drift detection workflow defines matrix across all 7 infrastructure modules" {
  for mod in oci cloudflare gcp azure homelab github monitoring; do
    run yq eval ".jobs.drift-detect.strategy.matrix.module[] | select(. == \"$mod\")" "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "$mod" ]
  done
}

@test "drift detection workflow configures provider plugin caching" {
  run grep -E "actions/cache" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E "tofu-plugins" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "drift detection workflow uses tofu plan with detailed-exitcode and readonly lockfile" {
  run grep -E "tofu plan.*-detailed-exitcode" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -E -- "-lockfile=readonly" "$WORKFLOW"
  [ "$status" -eq 0 ]
}
