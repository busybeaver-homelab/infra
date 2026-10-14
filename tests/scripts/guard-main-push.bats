#!/usr/bin/env bats
# Tests for scripts/guard-main-push.sh (pre-push guard for refs/heads/main)

load 'helpers/test_helper'

GUARD="${REPO_ROOT}/scripts/guard-main-push.sh"
SHA_A="1111111111111111111111111111111111111111"
SHA_B="2222222222222222222222222222222222222222"

@test "allows pushes to feature branches" {
  run bash -c "printf 'refs/heads/feat/x %s refs/heads/feat/x %s\n' $SHA_A $SHA_B | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
  [ "$status" -eq 0 ]
}

@test "blocks a push to main without ALLOW_MAIN_PUSH" {
  run bash -c "printf 'refs/heads/main %s refs/heads/main %s\n' $SHA_A $SHA_B | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"direct push to refs/heads/main is blocked"* ]]
}

@test "blocks main when it is one of several pushed refs" {
  run bash -c "printf 'refs/heads/feat/x %s refs/heads/feat/x %s\nrefs/heads/main %s refs/heads/main %s\n' $SHA_A $SHA_B $SHA_A $SHA_B | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
  [ "$status" -eq 1 ]
}

@test "allows a deliberate owner push to main with ALLOW_MAIN_PUSH=1" {
  run bash -c "printf 'refs/heads/main %s refs/heads/main %s\n' $SHA_A $SHA_B | ALLOW_MAIN_PUSH=1 bash '$GUARD'"
  [ "$status" -eq 0 ]
}

@test "always refuses to delete main, even with ALLOW_MAIN_PUSH=1" {
  run bash -c "printf '(delete) %s refs/heads/main %s\n' 0000000000000000000000000000000000000000 $SHA_B | ALLOW_MAIN_PUSH=1 bash '$GUARD'"
  [ "$status" -eq 1 ]
}

@test "lefthook wires the guard into pre-push with stdin" {
  run yq '.pre-push.commands.guard-main-push.use_stdin' "${REPO_ROOT}/lefthook.yml"
  [ "$output" = "true" ]
  run yq '.pre-push.commands.guard-main-push.run' "${REPO_ROOT}/lefthook.yml"
  [[ "$output" == *"scripts/guard-main-push.sh"* ]]
}
