#!/usr/bin/env bats
# Codex native hooks use canonical Bash/MCP JSON; never execute fixture commands.
load 'helpers/test_helper'

setup() {
  setup_tmpdir
  CODEX_GUARD="$REPO_ROOT/.codex/hooks/agent-credential-guard.sh"
}
teardown() { teardown_tmpdir; }

codex_decision() {
  local expected="$1" command="$2" tool="${3:-Bash}" cwd="${4:-$REPO_ROOT}"
  jq -n --arg command "$command" --arg tool "$tool" --arg cwd "$cwd" \
    '{hook_event_name:"PreToolUse",tool_name:$tool,cwd:$cwd,tool_input:{command:$command}}' > "$BATS_TMPDIR/input.json"
  run --separate-stderr bash "$CODEX_GUARD" < "$BATS_TMPDIR/input.json"
  echo "case: $command ($tool); result: $status $output $stderr" >&2
  [ -z "$output" ] || return 1
  if [ "$expected" = allow ]; then
    [ "$status" -eq 0 ] && [ -z "$stderr" ]
  else
    [ "$status" -eq 2 ] && [ -n "$stderr" ]
  fi
}

@test "Codex guard allows App calls and local development with no override decision" {
  codex_decision allow 'scripts/agent-gh.sh pr list --json number'
  codex_decision allow 'scripts/agent-git.sh fetch origin refs/heads/main:refs/remotes/origin/main'
  codex_decision allow 'git status'
  codex_decision allow 'tofu validate' Bash "$REPO_ROOT/infrastructure/github"
  codex_decision allow 'tofu test' Bash "$REPO_ROOT/infrastructure/github"
  codex_decision allow 'tofu init -backend=false' Bash "$REPO_ROOT/infrastructure/github"
}

@test "Codex guard denies raw credential routes and shell composition" {
  local command
  for command in 'gh auth token' 'git push origin HEAD' 'echo "$(gh auth token)"' \
    'scripts/agent-gh.sh pr list && gh auth token' 'GH_TOKEN=x scripts/agent-gh.sh pr list' \
    'git -c alias.send=push send origin HEAD' 'tofu validate && tofu apply'; do
    codex_decision deny "$command" || return 1
  done
}

@test "Codex guard maps unsupported ask decisions to a blocking owner-run message" {
  local command
  for command in 'tofu plan' 'tofu apply' 'tofu destroy' 'tofu import x y' \
    'tofu state mv x y' 'tofu state rm x'; do
    codex_decision deny "$command" Bash "$REPO_ROOT/infrastructure/github" || return 1
    [[ "$stderr" == *'owner must run this operation directly'* ]] || return 1
    [[ "$stderr" != *'permissionDecision'* ]] || return 1
  done
}

@test "Codex guard covers MCP mutations and recognized reads" {
  codex_decision deny '' mcp__github__push_files
  codex_decision deny '' mcp__github__issue_write
  codex_decision deny '' mcp__github__unknown_new_write
  codex_decision allow '' mcp__github__issue_read
  codex_decision allow '' mcp__github__get_pull_request
}

@test "Codex guard blocks malformed input and missing classifier" {
  run --separate-stderr bash "$CODEX_GUARD" <<<'not-json'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  mkdir -p "$BATS_TMPDIR/repo/.codex/hooks"
  cp "$CODEX_GUARD" "$BATS_TMPDIR/repo/.codex/hooks/agent-credential-guard.sh"
  run --separate-stderr bash "$BATS_TMPDIR/repo/.codex/hooks/agent-credential-guard.sh" <<<'{}'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "Codex guard blocks unexpected classifier output and dependency errors" {
  mkdir -p "$BATS_TMPDIR/repo/.codex/hooks" "$BATS_TMPDIR/repo/.claude/hooks"
  cp "$CODEX_GUARD" "$BATS_TMPDIR/repo/.codex/hooks/agent-credential-guard.sh"
  local response
  for response in 'not-json' '{"hookSpecificOutput":{"permissionDecision":"allow"}}' \
    '{"hookSpecificOutput":{"permissionDecision":"ask"}}'; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" '\''%s'\''\n' "$response" > "$BATS_TMPDIR/repo/.claude/hooks/agent-credential-guard.sh"
    run --separate-stderr bash "$BATS_TMPDIR/repo/.codex/hooks/agent-credential-guard.sh" <<<'{}'
    [ "$status" -eq 2 ] || return 1
    [ -z "$output" ] || return 1
  done
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TMPDIR/repo/.claude/hooks/agent-credential-guard.sh"
  run --separate-stderr bash "$BATS_TMPDIR/repo/.codex/hooks/agent-credential-guard.sh" <<<'{}'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "Codex project hook is synchronous and covers canonical Bash and MCP names" {
  run jq -e '.hooks.PreToolUse | length == 1' "$REPO_ROOT/.codex/hooks.json"
  [ "$status" -eq 0 ]
  local matcher
  matcher="$(jq -r '.hooks.PreToolUse[0].matcher' "$REPO_ROOT/.codex/hooks.json")"
  [[ Bash =~ $matcher ]] || false
  [[ mcp__github__issue_write =~ $matcher ]] || false
  run jq -e '.hooks.PreToolUse[0].hooks[0] | .type == "command" and (.async != true) and (.command | contains(".codex/hooks/agent-credential-guard.sh"))' "$REPO_ROOT/.codex/hooks.json"
  [ "$status" -eq 0 ]
}

@test "Codex guard configuration and adapter are owned security boundaries" {
  run grep -E '^/\.codex/[[:space:]]+@busybeaver$' "$REPO_ROOT/.github/CODEOWNERS"
  [ "$status" -eq 0 ]
  run grep -F '/hooks' "$REPO_ROOT/docs/runbooks/ci-workflows-standards.md"
  [ "$status" -eq 0 ]
}

@test "Codex guard gates infrastructure operations even when session cwd is outside github" {
  codex_decision deny 'tofu plan' Bash "$REPO_ROOT"
  codex_decision deny 'tofu plan' Bash "$REPO_ROOT/infrastructure/gcp"
  codex_decision deny 'tofu console' Bash "$REPO_ROOT"
}

@test "Codex configured launcher blocks when Git root or adapter is unavailable" {
  local launcher
  launcher="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$REPO_ROOT/.codex/hooks.json")"
  mkdir "$BATS_TMPDIR/not-a-repo" "$BATS_TMPDIR/empty-repo"
  run git -C "$BATS_TMPDIR/empty-repo" init -q
  [ "$status" -eq 0 ]
  cd "$BATS_TMPDIR/not-a-repo"
  run --separate-stderr bash -c "$launcher" <<<'{}'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  cd "$BATS_TMPDIR/empty-repo"
  run --separate-stderr bash -c "$launcher" <<<'{}'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}
