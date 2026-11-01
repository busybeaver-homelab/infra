#!/usr/bin/env bats
# Tests for scripts/check-workflow-environments.sh (design 4.7)

load 'helpers/test_helper'

SCRIPT="${REPO_ROOT}/scripts/check-workflow-environments.sh"

setup() {
  WF_DIR="${BATS_TEST_TMPDIR}/workflows"
  mkdir -p "$WF_DIR"
}

# write_workflow <file> <environment-yaml-fragment-or-empty>
write_workflow() {
  local file="$1" env_block="${2:-}"
  {
    printf 'name: Fixture\non: push\njobs:\n  example-job:\n    runs-on: ubuntu-latest\n'
    [[ -n "$env_block" ]] && printf '%s\n' "$env_block"
    printf '    steps:\n      - run: echo ok\n'
  } >"${WF_DIR}/${file}"
}

@test "check-workflow-environments.sh exists, is executable, and passes shellcheck and shfmt" {
  [ -x "$SCRIPT" ]
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
  run shfmt -d -i 2 -ci "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]] || false
  [[ "$output" =~ "--workflows-dir" ]] || false
}

@test "passes when workflows use only unprotected environments or none" {
  write_workflow plain.yml ""
  write_workflow ci.yml "    environment: ci"
  write_workflow hb.yaml "    environment: heartbeat"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 0 ]
}

@test "fails and names file and job for static ops in an unowned workflow" {
  write_workflow rogue.yml "    environment: ops"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:example-job"* ]] || false
}

@test "fails for static backup in an unowned workflow" {
  write_workflow rogue.yml "    environment: backup"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:example-job"* ]] || false
}

@test "fails for the map form environment: {name: backup}" {
  write_workflow rogue.yml $'    environment:\n      name: backup'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:example-job"* ]] || false
}

@test "fails for the flow map form with url" {
  write_workflow rogue.yml '    environment: {name: ops, url: "https://example.test"}'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:example-job"* ]] || false
}

@test "matches protected names case-insensitively and ignores surrounding whitespace" {
  write_workflow upper.yml "    environment: OPS"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"upper.yml:example-job"* ]] || false
  rm "${WF_DIR}/upper.yml"
  write_workflow spaced.yml '    environment: " Backup "'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spaced.yml:example-job"* ]] || false
}

@test "fails for a dynamic environment expression in string and map form" {
  write_workflow dyn-string.yml '    environment: ${{ inputs.env }}'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dyn-string.yml:example-job"* ]] || false
  rm "${WF_DIR}/dyn-string.yml"

  write_workflow dyn-map.yml $'    environment:\n      name: ${{ github.event.inputs.target }}'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dyn-map.yml:example-job"* ]] || false
}

@test "fails for a dynamic environment expression even in an allowlisted workflow" {
  write_workflow backup-prune.yml '    environment: ${{ inputs.env }}'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup-prune.yml:example-job"* ]] || false
}

@test "fails for a protected environment reached through a YAML alias" {
  cat >"${WF_DIR}/alias.yml" <<'YAML'
name: Fixture
on: push
x-env: &protected ops
jobs:
  aliased-job:
    runs-on: ubuntu-latest
    environment: *protected
    steps:
      - run: echo ok
YAML
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"alias.yml:aliased-job"* ]] || false
}

@test "allowlisted backup workflows may use ops and backup" {
  write_workflow backup-dr-copy.yml "    environment: ops"
  write_workflow backup-prune.yml $'    environment:\n      name: backup'
  write_workflow ci.yml "    environment: ci"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 0 ]
}

@test "allowlist matches the exact file name only" {
  write_workflow backup-prune.yaml "    environment: ops"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup-prune.yaml:example-job"* ]] || false
}

@test "lists every offender, not only the first" {
  write_workflow one.yml "    environment: ops"
  write_workflow two.yml "    environment: backup"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"one.yml:example-job"* ]] || false
  [[ "$output" == *"two.yml:example-job"* ]] || false
}

# write_caller <file> <uses-target>: a job that calls a reusable workflow.
write_caller() {
  printf 'name: Fixture\non: push\njobs:\n  caller-job:\n    uses: %s\n' "$2" >"${WF_DIR}/$1"
}

@test "fails for a remote reusable workflow call, whose environment this check cannot see" {
  write_caller rogue.yml "example-org/example-repo/.github/workflows/deploy.yml@0123456789abcdef0123456789abcdef01234567"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:caller-job"* ]] || false
}

@test "fails for a remote reusable workflow call even in an allowlisted workflow" {
  write_caller backup-prune.yml "example-org/example-repo/.github/workflows/deploy.yml@0123456789abcdef0123456789abcdef01234567"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"backup-prune.yml:caller-job"* ]] || false
}

@test "fails when an unowned workflow calls an allowlisted backup workflow" {
  write_workflow backup-dr-copy.yml "    environment: ops"
  write_caller rogue.yml "./.github/workflows/backup-dr-copy.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:caller-job"* ]] || false
}

@test "passes for a local reusable workflow call to a checked, unprotected workflow" {
  write_workflow shared.yml "    environment: ci"
  write_caller caller.yml "./.github/workflows/shared.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 0 ]
}

@test "the real repository workflows satisfy the policy" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$SCRIPT" --workflows-dir "${REPO_ROOT}/.github/workflows"
  [ "$status" -eq 0 ]
}

@test "fails closed with exit 2 on malformed YAML" {
  write_workflow ok.yml ""
  printf 'name: Broken\njobs:\n  a: [unclosed\n' >"${WF_DIR}/broken.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"broken.yml"* ]] || false
}

@test "fails closed with exit 2 when a workflow has no jobs mapping" {
  printf 'name: NoJobs\non: push\n' >"${WF_DIR}/nojobs.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nojobs.yml"* ]] || false
}

@test "fails closed with exit 2 for a missing directory or an empty one" {
  run "$SCRIPT" --workflows-dir "${BATS_TEST_TMPDIR}/does-not-exist"
  [ "$status" -eq 2 ]
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 2 ]
}

@test "rejects unknown arguments and a missing option value" {
  run "$SCRIPT" --bogus
  [ "$status" -ne 0 ]
  run "$SCRIPT" --workflows-dir
  [ "$status" -ne 0 ]
}

@test "does not print environment expressions or step contents" {
  write_workflow rogue.yml '    environment: ${{ secrets.EXAMPLE_NAME }}'
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" != *"secrets.EXAMPLE_NAME"* ]] || false
  [[ "$output" != *"echo ok"* ]] || false
}
