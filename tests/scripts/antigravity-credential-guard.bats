#!/usr/bin/env bats
# Native Antigravity tool calls are fixtures; their commands are never executed.
load 'helpers/test_helper'
setup() {
  setup_tmpdir
  AG_GUARD="$REPO_ROOT/.agent/hooks/antigravity-credential-guard.py"
}
teardown() { teardown_tmpdir; }

ag_call() {
  local decision="$1" tool="$2" args="$3"
  jq -n --arg tool "$tool" --argjson args "$args" \
    '{toolCall:{name:$tool,args:$args},workspacePaths:["/tmp/example"]}' > "$BATS_TMPDIR/input.json"
  run --separate-stderr python3 "$AG_GUARD" < "$BATS_TMPDIR/input.json"
  [ "$status" -eq 0 ] || return 1
  [ -z "$stderr" ] || return 1
  printf '%s' "$output" | jq -e --arg decision "$decision" \
    '.decision == $decision and (has("permissionOverrides") | not) and (has("overwrite") | not)' >/dev/null
}

ag_command() {
  local expected="$1" command="$2" cwd="${3:-$REPO_ROOT}"
  local args
  args="$(jq -n --arg command "$command" --arg cwd "$cwd" '{CommandLine:$command,Cwd:$cwd}')"
  echo "case: $command" >&2
  ag_call "$expected" run_command "$args"
}

@test "Antigravity allows wrappers and local development through default policy" {
  ag_command allow 'scripts/agent-gh.sh pr list --json number'
  ag_command allow 'scripts/agent-git.sh push -u origin HEAD'
  ag_command allow 'git status'
  ag_command allow 'tofu validate' "$REPO_ROOT/infrastructure/github"
  ag_command allow 'tofu test' "$REPO_ROOT/infrastructure/github"
  ag_command allow 'tofu init -backend=false' "$REPO_ROOT/infrastructure/github"
  ag_call allow view_file '{"AbsolutePath":"/tmp/example.txt"}'
}

@test "Antigravity denies owner credentials raw transport and shell composition" {
  local command
  for command in 'gh auth token' 'git push origin HEAD' 'g"h" auth token' \
    'scripts/agent-gh.sh pr list && gh auth token' 'echo "$(gh auth token)"' \
    'GH_TOKEN=x scripts/agent-gh.sh pr list' 'git -c alias.send=push send origin HEAD'; do
    ag_command deny "$command" || return 1
  done
}

@test "Antigravity force asks for each sensitive call ignoring cached grants" {
  local command
  for command in 'tofu plan' 'tofu apply' 'tofu destroy' 'tofu import x y' \
    'tofu state mv x y' 'tofu state rm x' 'tofu console'; do
    ag_command force_ask "$command" "$REPO_ROOT/infrastructure/github" || return 1
  done
  ag_command allow 'tofu plan' "$REPO_ROOT/infrastructure/gcp"
}

@test "Antigravity uses native Cwd rather than workspace metadata" {
  ag_command force_ask 'tofu -chdir=infrastructure/github plan'
  ag_command force_ask 'tofu -chdir=../github plan' "$REPO_ROOT/infrastructure/gcp"
}

@test "Antigravity covers native and normalized GitHub MCP names" {
  ag_call deny mcp__github__issue_write '{}'
  ag_call deny mcp_github_push_files '{}'
  ag_call deny mcp__github__unknown_new_write '{}'
  ag_call allow mcp__github__issue_read '{}'
  ag_call allow mcp_github_get_pull_request '{}'
  ag_call allow mcp__example__read_file '{}'
}

@test "Antigravity blocks interactive task input but allows task status" {
  ag_call deny manage_task '{"Action":"send_input","Input":"gh auth token","TaskId":"example"}'
  ag_call allow manage_task '{"Action":"status","TaskId":"example"}'
}

@test "Antigravity emits a valid deny for malformed or incomplete payloads" {
  local payload
  for payload in 'not-json' '{}' '[]' '{"toolCall":{"name":"run_command","args":{}}}' \
    '{"toolCall":{"name":"run_command","args":{"CommandLine":"git status","Cwd":"relative"}}}' \
    '{"toolCall":{"name":"run_command","args":{"CommandLine":4,"Cwd":"/tmp"}}}'; do
    run --separate-stderr python3 "$AG_GUARD" <<< "$payload"
    [ "$status" -eq 0 ] || return 1
    [ -z "$stderr" ] || return 1
    printf '%s' "$output" | jq -e '.decision == "deny"' >/dev/null || return 1
  done
}

@test "Antigravity blocks missing failing or malformed classifier without leaking input" {
  mkdir -p "$BATS_TMPDIR/repo/.agent/hooks" "$BATS_TMPDIR/repo/.claude/hooks"
  cp "$AG_GUARD" "$BATS_TMPDIR/repo/.agent/hooks/antigravity-credential-guard.py"
  local adapter="$BATS_TMPDIR/repo/.agent/hooks/antigravity-credential-guard.py" response
  for response in missing failing malformed; do
    case "$response" in
      missing) rm -f "$BATS_TMPDIR/repo/.claude/hooks/agent-credential-guard.sh" ;;
      failing) printf '#!/usr/bin/env bash\nexit 42\n' > "$BATS_TMPDIR/repo/.claude/hooks/agent-credential-guard.sh" ;;
      malformed) printf '#!/usr/bin/env bash\nprintf "%%s" not-json\n' > "$BATS_TMPDIR/repo/.claude/hooks/agent-credential-guard.sh" ;;
    esac
    run --separate-stderr python3 "$adapter" <<<'{"toolCall":{"name":"run_command","args":{"CommandLine":"echo synthetic-private-input","Cwd":"/tmp"}}}'
    [ "$status" -eq 0 ] || return 1
    [ -z "$stderr" ] || return 1
    printf '%s' "$output" | jq -e '.decision == "deny"' >/dev/null || return 1
    [[ "$output" != *synthetic-private-input* ]] || return 1
  done
}

@test "Antigravity launcher denies unavailable Git root or adapter with native JSON" {
  local launcher
  launcher="$(jq -r '."agent-credential-guard".PreToolUse[0].hooks[0].command' "$REPO_ROOT/.agents/hooks.json")"
  mkdir "$BATS_TMPDIR/empty-repo" "$BATS_TMPDIR/not-a-repo"
  git -C "$BATS_TMPDIR/empty-repo" init -q
  local directory
  for directory in empty-repo not-a-repo; do
    cd "$BATS_TMPDIR/$directory"
    run --separate-stderr bash -c "$launcher" <<<'{}'
    [ "$status" -eq 0 ] || return 1
    printf '%s' "$output" | jq -e '.decision == "deny"' >/dev/null || return 1
  done
}

@test "Antigravity native configuration matches every tool and is owned" {
  run jq -e '."agent-credential-guard" | .enabled == true and (.PreToolUse | length == 1) and .PreToolUse[0].matcher == "*" and .PreToolUse[0].hooks[0].type == "command"' "$REPO_ROOT/.agents/hooks.json"
  [ "$status" -eq 0 ]
  run grep -E '^/\.agents/hooks.json[[:space:]]+@busybeaver$' "$REPO_ROOT/.github/CODEOWNERS"
  [ "$status" -eq 0 ]
  run grep -E '^/\.agent/hooks/[[:space:]]+@busybeaver$' "$REPO_ROOT/.github/CODEOWNERS"
  [ "$status" -eq 0 ]
}

@test "Antigravity converts classifier timeout to native deny without a traceback" {
  run --separate-stderr python3 - "$AG_GUARD" <<'PY'
import importlib.util
import io
import json
import subprocess
import sys
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("guard", sys.argv[1])
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
payload = {"toolCall": {"name": "run_command", "args": {"CommandLine": "git status", "Cwd": "/tmp"}}}
with patch.object(guard.subprocess, "run", side_effect=subprocess.TimeoutExpired("policy", 5)):
    with patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
        guard.main()
PY
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  printf '%s' "$output" | jq -e '.decision == "deny"' >/dev/null
}
