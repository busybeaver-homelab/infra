#!/usr/bin/env bats
load 'helpers/test_helper'
load 'helpers/agent_app'

setup() {
  setup_agent_app
  WRAPPER="$REPO_ROOT/scripts/agent-worktree-identity.sh"
  MAIN="$BATS_TEST_TMPDIR/main"
  WORKTREE="$BATS_TEST_TMPDIR/agent worktree"
  git init -q --initial-branch=main "$MAIN"
  git -C "$MAIN" config user.name 'Fixture Owner'
  git -C "$MAIN" config user.email owner@example.test
  git -C "$MAIN" config commit.gpgsign false
  git -C "$MAIN" commit -qm 'test: seed fixture' --allow-empty
  git -C "$MAIN" config commit.gpgsign true
  git -C "$MAIN" worktree add -qb test/agent "$WORKTREE"
}

@test "sets bot identity and unsigned commits only in the target worktree" {
  run bash "$WRAPPER" "$WORKTREE"
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORKTREE" config user.name)" = 'example-agent[bot]' ]
  [ "$(git -C "$WORKTREE" config user.email)" = '424242+example-agent[bot]@users.noreply.github.com' ]
  [ "$(git -C "$WORKTREE" config commit.gpgsign)" = false ]
  [ "$(git -C "$MAIN" config user.name)" = 'Fixture Owner' ]
  [ "$(git -C "$MAIN" config commit.gpgsign)" = true ]
  [ "$(git -C "$MAIN" config extensions.worktreeConfig)" = true ]
}
@test "a real worktree commit has bot author and no signature" {
  run bash "$WRAPPER" "$WORKTREE"
  [ "$status" -eq 0 ]
  git -C "$WORKTREE" commit -qm 'test: bot fixture commit' --allow-empty
  [ "$(git -C "$WORKTREE" log -1 --format=%an)" = 'example-agent[bot]' ]
  [ "$(git -C "$WORKTREE" log -1 --format=%ae)" = '424242+example-agent[bot]@users.noreply.github.com' ]
  [ -z "$(git -C "$WORKTREE" cat-file commit HEAD | sed -n '/^gpgsig /p')" ]
}
@test "identity setup is idempotent" {
  bash "$WRAPPER" "$WORKTREE"
  local before
  before="$(git -C "$WORKTREE" config --worktree --list)"
  bash "$WRAPPER" "$WORKTREE"
  [ "$(git -C "$WORKTREE" config --worktree --list)" = "$before" ]
}
@test "missing app metadata changes no git configuration" {
  APP_MINT_FAIL=1 run bash "$WRAPPER" "$WORKTREE"
  [ "$status" -eq 3 ]
  [ "$(git -C "$WORKTREE" config user.name)" = 'Fixture Owner' ]
  run git -C "$MAIN" config --get extensions.worktreeConfig
  [ "$status" -eq 1 ]
}
@test "refuses the main checkout rather than changing owner identity" {
  run bash "$WRAPPER" "$MAIN"
  [ "$status" -eq 64 ]
  [ "$(git -C "$MAIN" config user.name)" = 'Fixture Owner' ]
}
@test "refuses a missing worktree" {
  run bash "$WRAPPER" "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 64 ]
}
