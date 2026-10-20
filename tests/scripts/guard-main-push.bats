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

ZERO_SHA="0000000000000000000000000000000000000000"

# Builds a repo where refs/remotes/origin/main is one commit ahead of the
# fork point of feat/ci/stale-branch, and prints that branch's tip SHA.
stale_feature_repo() {
  local repo="$1"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config commit.gpgsign false
  echo "base" > "${repo}/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "chore: initial"

  git -C "$repo" checkout -q -b feat/ci/stale-branch
  echo "feature" > "${repo}/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m "feat: add feature"

  git -C "$repo" checkout -q main
  echo "upstream change" >> "${repo}/file.txt"
  git -C "$repo" commit -q -am "feat: upstream commit on main"
  git -C "$repo" update-ref refs/remotes/origin/main main
  git -C "$repo" rev-parse feat/ci/stale-branch
}

# Runs the guard inside <repo> with one pre-push stdin line:
# push_line <repo> <local ref> <local sha> <remote ref> <remote sha>
push_line() {
  run bash -c "cd '$1' && printf '%s %s %s %s\n' '$2' '$3' '$4' '$5' | env -u ALLOW_MAIN_PUSH bash '$GUARD'"
}

@test "blocks creating a remote branch whose tip is behind refs/remotes/origin/main" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  sha="$(stale_feature_repo "$repo")"
  push_line "$repo" refs/heads/feat/ci/stale-branch "$sha" refs/heads/feat/ci/stale-branch "$ZERO_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is behind refs/remotes/origin/main"* ]] || false
}

@test "allows creating a remote branch rebased onto refs/remotes/origin/main" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  stale_feature_repo "$repo" >/dev/null
  git -C "$repo" rebase -q main feat/ci/stale-branch
  sha="$(git -C "$repo" rev-parse HEAD)"
  push_line "$repo" refs/heads/feat/ci/stale-branch "$sha" refs/heads/feat/ci/stale-branch "$ZERO_SHA"
  [ "$status" -eq 0 ]
}

@test "allows a follow-up push to an existing remote branch that is behind origin/main" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  sha="$(stale_feature_repo "$repo")"
  push_line "$repo" refs/heads/feat/ci/stale-branch "$sha" refs/heads/feat/ci/stale-branch "$SHA_B"
  [ "$status" -eq 0 ]
}

@test "does not apply the ancestry check to tag pushes" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  sha="$(stale_feature_repo "$repo")"
  push_line "$repo" refs/tags/v0.1.0 "$sha" refs/tags/v0.1.0 "$ZERO_SHA"
  [ "$status" -eq 0 ]
}

@test "allows deleting a remote feature branch" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  stale_feature_repo "$repo" >/dev/null
  push_line "$repo" "(delete)" "$ZERO_SHA" refs/heads/feat/ci/stale-branch "$SHA_B"
  [ "$status" -eq 0 ]
}

@test "skips the ancestry check when the default remote ref is missing" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  sha="$(stale_feature_repo "$repo")"
  git -C "$repo" update-ref -d refs/remotes/origin/main
  push_line "$repo" refs/heads/feat/ci/stale-branch "$sha" refs/heads/feat/ci/stale-branch "$ZERO_SHA"
  [ "$status" -eq 0 ]
}

@test "names the configured GUARD_DEFAULT_REMOTE_REF in the error" {
  local repo="${BATS_TEST_TMPDIR}/repo" sha
  sha="$(stale_feature_repo "$repo")"
  git -C "$repo" update-ref refs/remotes/upstream/main main
  export GUARD_DEFAULT_REMOTE_REF=refs/remotes/upstream/main
  push_line "$repo" refs/heads/feat/ci/stale-branch "$sha" refs/heads/feat/ci/stale-branch "$ZERO_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is behind refs/remotes/upstream/main"* ]] || false
  [[ "$output" != *"origin/main"* ]]
}
