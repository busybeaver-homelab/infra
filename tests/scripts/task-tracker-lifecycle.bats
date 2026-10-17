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

@test ".agent/task.md is absent so docs/plans/task.md is the sole live tracker (R2-GOV-07)" {
  [ ! -e "$REPO_ROOT/.agent/task.md" ]
  cd "$REPO_ROOT"
  run git ls-files --error-unmatch .agent/task.md
  [ "$status" -ne 0 ]
}

@test "all plan files under docs/plans/ follow YYYY-MM-DD-kebab-case.md naming without underscores (R2-GOV-07)" {
  cd "$REPO_ROOT"
  while IFS= read -r file; do
    local base
    base="$(basename "$file")"
    [ "$base" = "task.md" ] && continue
    [[ "$base" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+(-design|-plan)?\.md$ ]] || {
      echo "Non-conforming plan filename: $file" >&2
      return 1
    }
  done < <(git ls-files ':(glob)docs/plans/*.md')

  while IFS= read -r file; do
    local base
    base="$(basename "$file")"
    [[ "$base" =~ ^task-20[0-9]{2}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$ ]] || {
      echo "Non-conforming archived task filename: $file" >&2
      return 1
    }
  done < <(git ls-files ':(glob)docs/plans/archive/*.md')
}

@test "no tracked file leaks local macOS workstation paths (X-10)" {
  cd "$REPO_ROOT"
  # Construct regex via concatenation so this test file itself does not match a literal /Users/<username> path.
  local pat="/Users""/[A-Za-z0-9._-]+"
  run bash -c "git grep -I -n -E '${pat}' -- ':!tests/scripts/task-tracker-lifecycle.bats' | grep -v '/Users/runner' || true"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
