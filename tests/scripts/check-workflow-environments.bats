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

@test "checks dotfile and upper-case extension workflow files" {
  write_workflow .hidden.yml "    environment: ops"
  write_workflow LOUD.YML "    environment: backup"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *".hidden.yml:example-job"* ]] || false
  [[ "$output" == *"LOUD.YML:example-job"* ]] || false
}

@test "fails for a protected environment pulled in through a YAML merge key" {
  printf 'name: Fixture\non: push\nx-env: &protected\n  environment: ops\njobs:\n  merged-job:\n    <<: *protected\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n' >"${WF_DIR}/rogue.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:merged-job"* ]] || false
}

@test "fails when another workflow defines a job reporting the Workflow Policy check name" {
  printf 'name: Fixture\non: push\njobs:\n  spoof:\n    name: workflow policy\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/rogue.yml"
  printf 'name: Fixture\non: push\njobs:\n  Workflow Policy:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/rogue2.yml"
  printf 'name: Workflow Policy\non: push\njobs:\n  workflow-policy:\n    name: Workflow Policy\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/workflow-policy.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:spoof"* ]] || false
  [[ "$output" == *"rogue2.yml:Workflow Policy"* ]] || false
  [[ "$output" != *"workflow-policy.yml:"* ]] || false
}

@test "fails for expression job names that could evaluate to the Workflow Policy check name" {
  printf 'name: Fixture\non: push\njobs:\n  a:\n    name: ${{ '"'"'Workflow Policy'"'"' }}\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n  b:\n    name: Workflow ${{ '"'"'Policy'"'"' }}\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/rogue.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rogue.yml:a "* ]] || false
  [[ "$output" == *"rogue.yml:b "* ]] || false
}

@test "allows expression job names whose literal text rules out the Workflow Policy name" {
  printf 'name: Fixture\non: push\njobs:\n  molecule:\n    name: Molecule (${{ matrix.scenario }})\n    runs-on: ubuntu-latest\n    strategy:\n      matrix:\n        scenario: [one]\n    steps:\n      - run: "true"\n' >"${WF_DIR}/matrix.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 0 ]
}

@test "fails for any workflow granting statuses or checks write, which could post the required check" {
  printf 'name: Fixture\non: push\njobs:\n  job-scope:\n    runs-on: ubuntu-latest\n    permissions:\n      statuses: write\n    steps:\n      - run: "true"\n' >"${WF_DIR}/statuses.yml"
  printf 'name: Fixture\non: push\npermissions: write-all\njobs:\n  plain:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/writeall.yml"
  printf 'name: Fixture\non: push\njobs:\n  check-scope:\n    runs-on: ubuntu-latest\n    permissions:\n      checks: write\n    steps:\n      - run: "true"\n' >"${WF_DIR}/checks.yml"
  run "$SCRIPT" --workflows-dir "$WF_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"statuses.yml:job-scope"* ]] || false
  [[ "$output" == *"writeall.yml:(workflow)"* ]] || false
  [[ "$output" == *"checks.yml:check-scope"* ]] || false
}

@test "allows read-only checks and statuses permissions" {
  printf 'name: Fixture\non: push\npermissions:\n  checks: read\n  statuses: read\njobs:\n  plain:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' >"${WF_DIR}/readonly.yml"
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
