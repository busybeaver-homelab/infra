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

@test "AGENTS.md documents the owner local-merge command the guard expects" {
  local doc="${REPO_ROOT}/AGENTS.md"
  run grep -F 'git merge --ff-only <branch> && ALLOW_MAIN_PUSH=1 git push origin main' "$doc"
  [ "$status" -eq 0 ]
  run grep -F 'ALLOW_MAIN_PUSH' "$GUARD"
  [ "$status" -eq 0 ]
  run grep -F 'lefthook install' "$doc"
  [ "$status" -eq 0 ]
}

@test "blocks pushing a feature branch that is behind refs/remotes/origin/main" {
  local repo="${BATS_TEST_TMPDIR}/stale-repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo "base" > "${repo}/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "chore: initial"

  git -C "$repo" checkout -q -b feat/ci/stale-branch
  echo "feature" > "${repo}/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: add feature"
  local feat_sha
  feat_sha="$(git -C "$repo" rev-parse HEAD)"

  git -C "$repo" checkout -q main
  echo "upstream change" >> "${repo}/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "feat: upstream commit on main"
  local main_sha
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" update-ref refs/remotes/origin/main "$main_sha"

  run bash -c "cd '$repo' && printf 'refs/heads/feat/ci/stale-branch %s refs/heads/feat/ci/stale-branch 0000000000000000000000000000000000000000\n' '$feat_sha' | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"behind origin/main"* ]] || false
}

@test "allows pushing a feature branch that includes refs/remotes/origin/main" {
  local repo="${BATS_TEST_TMPDIR}/rebased-repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo "base" > "${repo}/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "chore: initial"

  echo "upstream change" >> "${repo}/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "feat: upstream commit on main"
  local main_sha
  main_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" update-ref refs/remotes/origin/main "$main_sha"

  git -C "$repo" checkout -q -b feat/ci/fresh-branch refs/remotes/origin/main
  echo "feature" > "${repo}/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: add feature"
  local feat_sha
  feat_sha="$(git -C "$repo" rev-parse HEAD)"

  run bash -c "cd '$repo' && printf 'refs/heads/feat/ci/fresh-branch %s refs/heads/feat/ci/fresh-branch 0000000000000000000000000000000000000000\n' '$feat_sha' | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
  [ "$status" -eq 0 ]
}

