#!/usr/bin/env bats

load 'helpers/test_helper'

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "docs/plans/task.md is ignored by git" {
  cd "$REPO_ROOT"
  run git check-ignore -q docs/plans/task.md
  [ "$status" -eq 0 ]
}

@test "docs/plans/archive directory files are tracked by git" {
  cd "$REPO_ROOT"
  run git check-ignore -q docs/plans/archive/task-sample.md
  [ "$status" -ne 0 ]
}

@test "docs/plans/task.md does not exist in repository git index" {
  cd "$REPO_ROOT"
  run git ls-files --error-unmatch docs/plans/task.md
  [ "$status" -ne 0 ]
}
