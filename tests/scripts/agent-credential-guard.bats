#!/usr/bin/env bats
# Commands are JSON fixtures sent to the hook; none are executed.
load 'helpers/test_helper'

setup() {
  setup_tmpdir
  GUARD_ROOT="${AGENT_GUARD_FIXTURE_ROOT:-$REPO_ROOT}"
  GUARD="${GUARD_ROOT}/.claude/hooks/agent-credential-guard.sh"
  SETTINGS="${GUARD_ROOT}/.claude/settings.json"
}
teardown() { teardown_tmpdir; }

check_decision() {
  local expected="$1" command="$2" cwd="${3:-$REPO_ROOT}" tool="${4:-Bash}"
  jq -n --arg command "$command" --arg cwd "$cwd" --arg tool "$tool" \
    '{tool_name:$tool,cwd:$cwd,tool_input:{command:$command}}' > "$BATS_TMPDIR/input.json"
  run --separate-stderr bash "$GUARD" < "$BATS_TMPDIR/input.json"
  echo "case: $command ($cwd); result: $status $output $stderr" >&2
  case "$expected" in
    deny) [ "$status" -eq 2 ] && [ -z "$output" ] && [[ "$stderr" == *"Agent credential guard:"* ]] ;;
    ask)
      [ "$status" -eq 0 ] || return 1
      printf '%s' "$output" | jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "ask" and (.permissionDecisionReason | length > 0)' >/dev/null ;;
    allow) [ "$status" -eq 0 ] && [ -z "$output" ] ;;
  esac
}

@test "guard denies direct gh and raw Git network operations" {
  local command
  for command in 'gh pr list' 'gh auth token' '/opt/homebrew/bin/gh pr list' 'mise exec gh -- gh pr list' \
    'git push origin x' 'git fetch origin main' 'git pull' 'git clone https://github.com/example/repo' \
    'git ls-remote origin' "git -c 'credential.helper=!gh auth git-credential' push" \
    'git -C /tmp/example push' 'env gh pr list' 'g"h" pr list' 'g\h pr list' 'echo $(gh auth token)' 'echo `gh auth token`' 'echo $(git push)'; do
    check_decision deny "$command" || return 1
  done
}

@test "guard denies owner credential reads and forbidden state dumps" {
  local command
  for command in "sops -d --extract '[\"github\"][\"token\"]' secrets/credentials.sops.yaml" \
    "sops --extract '[\"github\"][\"token\"]' secrets/credentials.sops.yaml" \
    'sops decrypt secrets/credentials.sops.yaml' \
    'security find-internet-password -s github.com -w' 'security find-generic-password -s gh:github.com -w' \
    'cat ~/.config/gh/hosts.yml' 'cat "$HOME/.config/gh/hosts.yml"' 'cat ~/Library/Application\ Support/gh/hosts.yml' \
    'git credential fill' 'git config --get credential.helper' \
    'tofu state pull' 'tofu show plan.bin' 'tofu output -json' 'git-crypt export-key /tmp/example'; do
    check_decision deny "$command" || return 1
  done
}

@test "guard denies unsafe wrapper forms and shell expansion without executing input" {
  local command
  for command in 'scripts/agent-gh.sh pr list; gh auth token' 'scripts/agent-gh.sh pr list && x' \
    'scripts/agent-gh.sh pr list || x' 'scripts/agent-gh.sh pr list | cat' 'scripts/agent-gh.sh $(id)' \
    'scripts/agent-gh.sh `id`' 'GH_TOKEN=x scripts/agent-gh.sh pr list' \
    'env scripts/agent-gh.sh pr list' 'bash scripts/agent-gh.sh pr list' \
    'scripts/agent-gh.sh pr list > /tmp/example' 'scripts/agent-gh.sh pr list & x' \
    $'scripts/agent-gh.sh pr list\nid' 'scripts/agent-gh.sh pr list # ignored' \
    'scripts/agent-gh.sh pr list "$GH_TOKEN"' 'scripts/agent-git.sh push origin *' \
    'echo x; scripts/agent-gh.sh pr list' 'scripts/agent-gh.sh pr list <(id)'; do
    check_decision deny "$command" || return 1
  done
  check_decision deny "scripts/agent-gh.sh \$(touch $BATS_TMPDIR/executed)"
  [ ! -e "$BATS_TMPDIR/executed" ]
}

@test "guard denies opaque infrastructure expansion" {
  check_decision deny 'tofu $ACTION'
  check_decision deny 'tofu $(echo apply)'
}

@test "guard requests per-invocation approval for infrastructure mutations" {
  local command
  for command in 'tofu apply' 'tofu destroy' 'tofu import example.resource id' \
    'tofu state mv old new' 'tofu state rm example.resource' \
    'mise exec -- tofu apply' '/opt/homebrew/bin/tofu apply' 'tofu -chdir=infrastructure/github apply'; do
    check_decision ask "$command" || return 1
  done
}

@test "guard requests approval for github plans and non-mock initialization" {
  check_decision ask 'tofu plan' "$REPO_ROOT/infrastructure/github"
  check_decision ask 'tofu plan' "$REPO_ROOT/infrastructure/github/tests"
  check_decision ask 'tofu -chdir=infrastructure/github plan'
  check_decision ask 'tofu -chdir=../github plan' "$REPO_ROOT/infrastructure/gcp"
  check_decision deny 'cd infrastructure/github && tofu plan'
  check_decision ask 'tofu refresh' "$REPO_ROOT/infrastructure/github"
  check_decision ask 'tofu console' "$REPO_ROOT/infrastructure/github"
  check_decision ask 'tofu workspace select example' "$REPO_ROOT/infrastructure/github"
  check_decision ask 'tofu init' "$REPO_ROOT/infrastructure/github"
  check_decision ask 'tofu init -backend=false -backend=true' "$REPO_ROOT/infrastructure/github"
}

@test "guard permits exact wrappers and ordinary local development" {
  local command
  for command in 'scripts/agent-gh.sh pr list --json number' 'scripts/agent-git.sh push -u origin HEAD' \
    'scripts/agent-gh.sh pr create --title "feat(example): add example" --body-file /tmp/example.md' \
    'git status' 'git commit -m x' 'git diff --no-textconv' 'mise exec -- bats tests/scripts/x.bats'; do
    check_decision allow "$command" || return 1
  done
  check_decision allow 'tofu plan' "$REPO_ROOT/infrastructure/gcp"
  check_decision allow 'tofu test' "$REPO_ROOT/infrastructure/github"
  check_decision allow 'tofu validate' "$REPO_ROOT/infrastructure/github"
  check_decision allow 'tofu init -backend=false' "$REPO_ROOT/infrastructure/github"
}

@test "guard fails closed on malformed or incomplete hook input without echoing it" {
  local payload
  for payload in 'not-json' '{}' '{"tool_name":"Bash","cwd":"/tmp","tool_input":{}}' \
    '{"tool_name":"Bash","cwd":null,"tool_input":{"command":"git status"}}'; do
    run --separate-stderr bash "$GUARD" <<< "$payload"
    [ "$status" -eq 2 ] || return 1
    [[ "$stderr" == *'Agent credential guard:'* ]] || return 1
    [[ "$output" != *"$payload"* ]] || return 1
  done
}

@test "settings deny every specified github write tool with a matching hook" {
  local tool matcher
  matcher="$(jq -r '.hooks.PreToolUse[] | select(.matcher != "Bash") | .matcher' "$SETTINGS")"
  for tool in merge_pull_request push_files create_or_update_file delete_file create_branch \
    create_pull_request update_pull_request delete_repository create_repository fork_repository \
    update_pull_request_branch pull_request_review_write; do
    run jq -e --arg tool "mcp__github__$tool" '.permissions.deny | index($tool) != null' "$SETTINGS"
    [ "$status" -eq 0 ] || return 1
    [[ "mcp__github__$tool" =~ $matcher ]] || return 1
    check_decision deny '' "$REPO_ROOT" "mcp__github__$tool" || return 1
  done
  check_decision allow '' "$REPO_ROOT" mcp__github__get_pull_request
}

@test "settings exclude only the two App wrappers with argument patterns" {
  run jq -e '.sandbox.excludedCommands | sort == ["scripts/agent-gh.sh *", "scripts/agent-git.sh *"]' "$SETTINGS"
  [ "$status" -eq 0 ]
  run jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[0] | .type == "command" and (.command | contains("$CLAUDE_PROJECT_DIR/.claude/hooks/agent-credential-guard.sh"))' "$SETTINGS"
  [ "$status" -eq 0 ]
}

@test "guard maps dependency failures to a blocking exit" {
  mkdir "$BATS_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 42\n' > "$BATS_TMPDIR/bin/python3"
  chmod +x "$BATS_TMPDIR/bin/python3"
  run env PATH="$BATS_TMPDIR/bin:$PATH" bash "$GUARD" <<<'{}'
  [ "$status" -eq 2 ]
  [[ "$output" == *'evaluation failed'* ]] || false
}

@test "guard denies quoted substitutions and compound sensitive invocations" {
  local command
  for command in 'echo "$(gh auth token)"' 'echo "$(git push)"' 'echo "$(tofu apply)"' \
    'echo "`gh auth token`"' 'cd infrastructure/github && tofu init' \
    'cd infrastructure/github && tofu console' 'tofu validate && tofu console' \
    'tofu init -backend=false && tofu init'; do
    check_decision deny "$command" || return 1
  done
}

@test "guard denies inline and unknown Git aliases" {
  check_decision deny 'git -c alias.send=push send origin HEAD'
  check_decision deny 'git send origin HEAD'
}

@test "guard blocks other and unknown github mutations but retains recognized reads" {
  local tool
  for tool in issue_write add_issue_comment actions_run_trigger unknown_new_write; do
    check_decision deny '' "$REPO_ROOT" "mcp__github__$tool" || return 1
  done
  check_decision allow '' "$REPO_ROOT" mcp__github__issue_read
  check_decision allow '' "$REPO_ROOT" mcp__github__pull_request_read
  check_decision allow '' "$REPO_ROOT" mcp__github__search_code
}
