#!/usr/bin/env bats
load 'helpers/test_helper'
load 'helpers/agent_routing'
setup() { setup_tmpdir; make_routing_fixture; }
teardown() { teardown_tmpdir; }
validate() { uv run --quiet --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-10-28; }
@test "routing accepts the approved model matrix" { run validate; [ "$status" -eq 0 ]; }
@test "routing validates with all client CLIs absent" {
  mkdir "$BATS_TMPDIR/bin"
  for name in codex claude antigravity curl; do printf '#!/bin/sh\necho called >> "%s"\nexit 99\n' "$BATS_TMPDIR/calls" > "$BATS_TMPDIR/bin/$name"; chmod +x "$BATS_TMPDIR/bin/$name"; done
  prepend_path "$BATS_TMPDIR/bin"
  run validate; [ "$status" -eq 0 ]; [ ! -e "$BATS_TMPDIR/calls" ]
}
@test "routing rejects a cheap reviewer" { sed -i.bak 's/model: opus/model: haiku/' "$BATS_TMPDIR/.claude/agents/routing-reviewer.md"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]; }
@test "routing rejects missing role models" { sed -i.bak '/^model =/d' "$BATS_TMPDIR/.codex/agents/routing-simple.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]; }
@test "routing rejects malformed native files" { printf '[broken\n' > "$BATS_TMPDIR/.codex/config.toml"; run validate; [ "$status" -eq 2 ]; [[ "$output" == *invalid_input* ]]; }
@test "routing rejects relaxed permission settings" { printf '\n[permissions]\ndefaultMode = "bypassPermissions"\n' >> "$BATS_TMPDIR/.codex/config.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_permissions* ]]; }
@test "routing preserves the shared policy import" { printf 'No import\n' > "$BATS_TMPDIR/CLAUDE.md"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *policy_import_missing* ]]; }
@test "routing rejects wrong coordinator and disabled checks" { sed -i.bak 's/enabled = true/enabled = false/; s/model = "gpt-6.1-sol"/model = "gpt-6-luna"/' "$BATS_TMPDIR/.codex/config.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* && "$output" == *unsafe_settings* ]]; }
@test "routing redacts invalid input" { printf '{SECRET_MARKER_INVALID' > "$BATS_TMPDIR/.claude/settings.json"; run validate; [ "$status" -eq 2 ]; [[ "$output" == *invalid_input* && "$output" != *SECRET_MARKER_INVALID* ]]; }
@test "routing warns when review is due" { run uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-11-27; [ "$status" -eq 0 ]; [[ "$output" == *model_review_due* ]]; }
@test "routing rejects worker inherit" { sed -i.bak 's/model = "gpt-6-luna"/model = "inherit"/' "$BATS_TMPDIR/.codex/agents/routing-simple.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]; }
@test "routing rejects unsupported effort" { sed -i.bak 's/medium/extreme/' "$BATS_TMPDIR/.codex/agents/routing-simple.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]; }
@test "routing rejects reviewer editing tools" { sed -i.bak 's/Read, Grep, Glob/Read, Edit/' "$BATS_TMPDIR/.claude/agents/routing-reviewer.md"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_permissions* ]]; }
@test "routing rejects unknown role files" { cp "$BATS_TMPDIR/.codex/agents/routing-simple.toml" "$BATS_TMPDIR/.codex/agents/routing-extra.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]; }
@test "routing rejects future reviews and invalid dates" { run uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-10-27; [ "$status" -eq 2 ]; [[ "$output" == *invalid_input* ]]; run uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of invalid; [ "$status" -eq 2 ]; }
@test "routing rejects blanket forced model" { printf '\nforced_subagent_model = "gpt-6-luna"\n' >> "$BATS_TMPDIR/.codex/config.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_settings* ]]; }
@test "routing rejects duplicate JSON keys in both orders" {
  for pair in '"opus", "model": "haiku"' '"haiku", "model": "opus"'; do
    printf '{"model": %s}' "$pair" > "$BATS_TMPDIR/.claude/settings.json"
    run validate; [ "$status" -eq 2 ]; [ "$output" = invalid_input ]
  done
}
@test "routing rejects duplicate manifest role keys" {
  python3 - "$BATS_TMPDIR/.agent-models.json" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); s=s.replace('"coordinator": {', '"coordinator": {}, "coordinator": {',1); p.write_text(s)
PY
  run validate; [ "$status" -eq 2 ]; [ "$output" = invalid_input ]
}
@test "routing rejects duplicate YAML keys in both orders" {
  for pair in $'model: haiku\nmodel: opus' $'model: opus\nmodel: haiku'; do
    sed -i.bak '/^model:/d' "$BATS_TMPDIR/.claude/agents/routing-reviewer.md"
    printf '%s\n' "$pair" | sed -i.bak '/^description:/r /dev/stdin' "$BATS_TMPDIR/.claude/agents/routing-reviewer.md"
    run validate; [ "$status" -eq 2 ]; [ "$output" = invalid_input ]
  done
}
@test "routing rejects codex model provider override" { printf '\nmodel_provider = "other"\n' >> "$BATS_TMPDIR/.codex/agents/routing-simple.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_settings* ]]; }
@test "routing rejects claude forced subagent model" { printf '{"model":"opus","env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}' > "$BATS_TMPDIR/.claude/settings.json"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_settings* ]]; }
@test "routing rejects claude force override" { printf '{"model":"opus","env":{"CLAUDE_CODE_SUBAGENT_MODEL_FORCE":"1"}}' > "$BATS_TMPDIR/.claude/settings.json"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_settings* ]]; }
@test "routing rejects antigravity reviewer edit and execution tools" {
  for tool in replace_file_content run_command; do
    sed -i.bak "s/^tools:.*/tools: [$tool]/" "$BATS_TMPDIR/.agents/agents/routing-reviewer.md"
    run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_permissions* ]]
  done
}
@test "routing accepts antigravity coordinator dispatch" {
  run validate; [ "$status" -eq 0 ]
}
@test "routing requires antigravity coordinator dispatch" {
  sed -i.bak 's/, invoke_subagent//' "$BATS_TMPDIR/.agents/agents/routing-coordinator.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
}
@test "routing rejects antigravity implementer dispatch" {
  sed -i.bak 's/^tools:.*/tools: [view_file, replace_file_content, run_command, invoke_subagent]/' "$BATS_TMPDIR/.agents/agents/routing-implementer.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
}
@test "routing rejects antigravity simple dispatch" {
  sed -i.bak 's/^tools:.*/tools: [view_file, replace_file_content, run_command, invoke_subagent]/' "$BATS_TMPDIR/.agents/agents/routing-simple.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
}
@test "routing rejects antigravity reviewer dispatch" {
  sed -i.bak 's/^tools:.*/tools: [view_file, grep_search, invoke_subagent]/' "$BATS_TMPDIR/.agents/agents/routing-reviewer.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
}
@test "routing rejects unknown wildcard and malformed tools" {
  for tool in unknown '*' null; do
    sed -i.bak "s/^tools:.*/tools: ['$tool']/" "$BATS_TMPDIR/.agents/agents/routing-simple.md"
    run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
  done
  sed -i.bak 's/^tools:.*/tools: [null]/' "$BATS_TMPDIR/.agents/agents/routing-simple.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]
}
@test "routing rejects cyclic and deep YAML without leaking" {
  sed -i.bak '/^description:/a\
loop: &loop [*loop]' "$BATS_TMPDIR/.agents/agents/routing-simple.md"
  run validate; [ "$status" -eq 2 ]; [ "$output" = invalid_input ]
  python3 - "$BATS_TMPDIR/.agents/agents/routing-simple.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text().replace('loop: &loop [*loop]', 'loop: ' + '['*1500 + 'SECRET_MARKER' + ']'*1500); p.write_text(s)
PY
  run validate; [ "$status" -eq 2 ]; [ "$output" = invalid_input ]
}
@test "routing accepts coherent owner-approved model refresh" {
  python3 - "$BATS_TMPDIR" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); f=p/'.agent-models.json'; m=json.loads(f.read_text())
for role in ('coordinator','reviewer'):
    e=m['providers']['codex']['roles'][role]; e['native_model']='synthetic-next-strong'; e['approved_resolved_models']=['synthetic-next-strong']
f.write_text(json.dumps(m))
for name in ('.codex/config.toml','.codex/agents/routing-reviewer.toml'):
    f=p/name; f.write_text(f.read_text().replace('gpt-6.1-sol','synthetic-next-strong'))
PY
  run validate; [ "$status" -eq 0 ]
}
@test "routing rejects native drift from refreshed manifest" {
  python3 - "$BATS_TMPDIR/.agent-models.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); m=json.loads(p.read_text())
for role in ('coordinator','reviewer'):
    m['providers']['codex']['roles'][role]['native_model']='synthetic-next-strong'
    m['providers']['codex']['roles'][role]['approved_resolved_models']=['synthetic-next-strong']
p.write_text(json.dumps(m))
PY
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]
}
@test "routing rejects mismatched reviewer resolutions" {
  python3 - "$BATS_TMPDIR/.agent-models.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); m=json.loads(p.read_text()); m['providers']['claude']['roles']['reviewer']['approved_resolved_models']=['synthetic-other']; p.write_text(json.dumps(m))
PY
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_manifest* ]]
}

set_source_url() {
  python3 - "$BATS_TMPDIR/.agent-models.json" "$1" "$2" <<'PYFIXTURE'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); m=json.loads(p.read_text())
m['providers'][sys.argv[2]]['roles']['simple']['source_urls']=[sys.argv[3]]
p.write_text(json.dumps(m))
PYFIXTURE
}
@test "routing rejects malformed documentation source URLs without leaking" {
  for url in 'not-a-url' 'https:///docs' 'https://[broken/docs' 'https://learn.chatgpt.com:invalid/docs' 'https://learn.chatgpt.com:/docs' 'https://learn.chatgpt.com/docs with spaces' 'https://learn.chatgpt.com/docs%ZZ'; do
    set_source_url codex "$url"
    run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
  done
}
@test "routing rejects non-HTTPS documentation sources" {
  for url in 'http://learn.chatgpt.com/docs' 'ftp://learn.chatgpt.com/docs' '//learn.chatgpt.com/docs' 'https://learn.chatgpt.com:444/docs'; do
    set_source_url codex "$url"
    run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
  done
}
@test "routing rejects credential-bearing documentation sources without leaking" {
  for url in 'https://SYNTHETIC_MARKER@learn.chatgpt.com/docs' 'https://user:SYNTHETIC_MARKER@learn.chatgpt.com/docs' 'https://@learn.chatgpt.com/docs'; do
    set_source_url codex "$url"
    run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
  done
}
@test "routing rejects non-vendor lookalike and cross-provider documentation origins" {
  for url in 'https://example.test/docs' 'https://learn.chatgpt.com.example.test/docs' 'https://learn-chatgpt.com/docs' 'https://code.claude.com/docs'; do
    set_source_url codex "$url"
    run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
  done
  set_source_url codex 'https://learn.chatgpt.com/docs'
  set_source_url claude 'https://developers.openai.com/docs'
  run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
  set_source_url codex 'https://learn.chatgpt.com/docs'
  set_source_url claude 'https://code.claude.com/docs'
  set_source_url antigravity 'https://ai.google.dev.example.test/docs'
  run validate; [ "$status" -eq 1 ]; [ "$output" = invalid_manifest ]
}
@test "routing accepts updated documentation paths on every approved official origin" {
  for url in 'https://learn.chatgpt.com/docs/updated?version=next#routing' 'https://developers.openai.com/docs/updated' 'https://platform.openai.com/docs/updated' 'https://LEARN.CHATGPT.COM:443/docs/updated'; do
    set_source_url codex "$url"
    run validate; [ "$status" -eq 0 ]
  done
  for url in 'https://code.claude.com/docs/updated' 'https://platform.claude.com/docs/updated'; do
    set_source_url claude "$url"
    run validate; [ "$status" -eq 0 ]
  done
  for url in 'https://antigravity.google/docs/updated' 'https://www.antigravity.google/docs/updated' 'https://ai.google.dev/docs/updated'; do
    set_source_url antigravity "$url"
    run validate; [ "$status" -eq 0 ]
  done
}

@test "real Codex configuration follows manifest with one active delegate" {
  run python3 - "$REPO_ROOT" <<'PY'
import json, pathlib, sys, tomllib
p = pathlib.Path(sys.argv[1]); roles = json.loads((p/'.agent-models.json').read_text())['providers']['codex']['roles']
c = tomllib.loads((p/'.codex/config.toml').read_text()); a = c['agents']
assert (c['model'], c['model_reasoning_effort']) == (roles['coordinator']['native_model'], roles['coordinator']['reasoning_effort'])
assert a['enabled'] is True and a['max_concurrent_threads_per_session'] == 1
assert (a['default_subagent_model'], a['default_subagent_reasoning_effort']) == (roles['implementer']['native_model'], roles['implementer']['reasoning_effort'])
for role in ('implementer', 'simple', 'reviewer'):
    r = tomllib.loads((p/f'.codex/agents/routing-{role}.toml').read_text())
    assert set(r) == {'name', 'description', 'developer_instructions', 'model', 'model_reasoning_effort'}
    assert r['name'] == f'routing-{role}' and r['description'] and r['developer_instructions']
    assert (r['model'], r['model_reasoning_effort']) == (roles[role]['native_model'], roles[role]['reasoning_effort'])
assert roles['reviewer']['native_model'] == roles['coordinator']['native_model']
PY
  [ "$status" -eq 0 ]
}

@test "shared policy requires delegation, escalation and independent review" {
  run python3 - "$REPO_ROOT/AGENTS.md" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text().lower()
for phrase in ('automatically delegate', 'one active writer', 'no nested workers', 'one unsuccessful simple correction', 'two unsuccessful implementer correction rounds', 'strong reviewer', 'exact verification commands', 'model mismatch', 'per-action human confirmation', 'no bypassing hooks', 'before edits, record the selected role, expected model, allowed scope, and acceptance checks in the ignored worktree-local docs/plans/task.md', 'update this evidence as routing and corrections advance'):
    assert phrase in s, phrase
PY
  [ "$status" -eq 0 ]
}

@test "real Claude configuration validates in a complete synthetic fixture" {
  [ -f "$REPO_ROOT/CLAUDE.md" ]
  [ -f "$REPO_ROOT/.claude/settings.json" ]
  cp "$REPO_ROOT/CLAUDE.md" "$BATS_TMPDIR/CLAUDE.md"
  cp "$REPO_ROOT/.claude/settings.json" "$BATS_TMPDIR/.claude/settings.json"
  for role in implementer simple reviewer; do
    [ -f "$REPO_ROOT/.claude/agents/routing-$role.md" ]
    cp "$REPO_ROOT/.claude/agents/routing-$role.md" "$BATS_TMPDIR/.claude/agents/"
  done
  run validate; [ "$status" -eq 0 ]
}

@test "real Claude settings and roles preserve guardrails and proactive routing" {
  run uv run --quiet --locked python - "$REPO_ROOT" <<'PY'
import json, pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
s = json.loads((p/'.claude/settings.json').read_text())
roles = json.loads((p/'.agent-models.json').read_text())['providers']['claude']['roles']
assert s['model'] == roles['coordinator']['native_model']
assert 'CLAUDE_CODE_SUBAGENT_MODEL' not in s.get('env', {})
assert 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE' not in s.get('env', {})
assert '@AGENTS.md' in (p/'CLAUDE.md').read_text()
for role in ('implementer', 'simple', 'reviewer'):
    text = (p/f'.claude/agents/routing-{role}.md').read_text()
    _, front, body = text.split('---', 2)
    agent = yaml.safe_load(front)
    assert agent['name'] == f'routing-{role}'
    assert agent['model'] == roles[role]['native_model']
    assert 'automatically' in agent['description'].lower()
    assert 'AGENTS.md' in body and 'task contract' in body.lower()
    assert 'permissionMode' not in agent
    tools = {x.strip() for x in agent['tools'].split(',')}
    assert tools == ({'Read', 'Grep', 'Glob'} if role == 'reviewer' else {'Read', 'Grep', 'Glob', 'Edit', 'Write', 'Bash'})
PY
  [ "$status" -eq 0 ]
}

@test "routing accepts existing Claude hooks and permissions" {
  python3 - "$BATS_TMPDIR/.claude/settings.json" <<'PYFIXTURE'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); s = json.loads(p.read_text())
s['hooks'] = {'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'true'}]}]}
s['permissions'] = {'deny': ['Bash(synthetic-guard)']}
p.write_text(json.dumps(s))
PYFIXTURE
  run validate; [ "$status" -eq 0 ]
}

@test "real Antigravity roles and always-on rule follow routing policy" {
  run uv run --quiet --locked python - "$REPO_ROOT" <<'PY'
import json, pathlib, sys, yaml
p = pathlib.Path(sys.argv[1]); roles = json.loads((p/'.agent-models.json').read_text())['providers']['antigravity']['roles']
for role in ('coordinator', 'implementer', 'simple', 'reviewer'):
    _, front, body = (p/f'.agents/agents/routing-{role}.md').read_text().split('---', 2)
    agent = yaml.safe_load(front)
    assert agent['model'] == roles[role]['native_model'] == ('pro' if role in ('coordinator', 'reviewer') else 'flash')
    assert agent['mainAgent'] is (role == 'coordinator') and agent['subagent'] is (role != 'coordinator')
    assert agent['commandExecutionPolicy'] == 'sandbox'
    assert 'AGENTS.md' in body and 'nested' in body.lower()
_, front, body = (p/'.agents/rules/model-routing.md').read_text().split('---', 2)
assert yaml.safe_load(front)['trigger'] == 'always_on'
for phrase in ('/agents', 'routing-coordinator', 'each new conversation', 'automatically', '.agent/AGENTS.md'):
    assert phrase in body, phrase
PY
  [ "$status" -eq 0 ]
}

@test "routing rejects Antigravity API alias as native tier" {
  sed -i.bak 's/model: flash/model: gemini-flash-latest/' "$BATS_TMPDIR/.agents/agents/routing-simple.md"
  run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]
}

@test "Antigravity adapter preserves sequential native and legacy delegation" {
  run python3 - "$REPO_ROOT/.agent/AGENTS.md" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text().lower()
for phrase in ('invoke_subagent', 'task_boundary', 'browser_subagent', 'wait', 'one active writer', 'no nested workers', 'two-round', 'strong coordinator'):
    assert phrase in s, phrase
PY
  [ "$status" -eq 0 ]
}

@test "Antigravity coordinator can dispatch and retains final assessment authority" {
  run uv run --quiet --locked python - "$REPO_ROOT" <<'PY'
import pathlib, sys, yaml
p = pathlib.Path(sys.argv[1])
for role in ('coordinator', 'implementer', 'simple', 'reviewer'):
    _, front, body = (p/f'.agents/agents/routing-{role}.md').read_text().split('---', 2)
    tools = yaml.safe_load(front)['tools']
    assert ('invoke_subagent' in tools) == (role == 'coordinator'), role
    if role == 'coordinator':
        for phrase in ('bounded', 'review', 'final assessment', 'git', 'root'):
            assert phrase in body.lower(), phrase
        assert 'claim final completion' not in body.lower()
PY
  [ "$status" -eq 0 ]
}

@test "routing keeps a 29-day review fresh" {
  run uv run --quiet --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-11-26
  [ "$status" -eq 0 ]; [[ "$output" != *model_review_due* ]]
}

@test "routing rejects an invalid stored review date" {
  python3 - "$BATS_TMPDIR/.agent-models.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); m = json.loads(p.read_text()); m['reviewed_on'] = 'not-a-date'; p.write_text(json.dumps(m))
PY
  run validate; [ "$status" -eq 2 ]; [[ "$output" == *invalid_input* ]]
}

@test "maintenance policy links and runbook exist" {
  run python3 - "$REPO_ROOT" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
root = (p / 'AGENTS.md').read_text().lower()
rule = (p / '.agents/rules/model-routing.md').read_text().lower()
assert 'docs/runbooks/agent-model-maintenance.md' in root
assert 'docs/runbooks/agent-model-maintenance.md' in rule
assert (p / 'docs/runbooks/agent-model-maintenance.md').is_file()
PY
  [ "$status" -eq 0 ]
}

@test "maintenance policy covers review triggers and owner approval" {
  local runbook="$REPO_ROOT/docs/runbooks/agent-model-maintenance.md"
  if is_git_crypt_encrypted "$runbook"; then
    skip 'runbook is git-crypt encrypted'
  fi
  run python3 - "$runbook" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text().lower()
for phrase in ('official', 'release', 'retirement', 'drift', 'owner approval', 'reviewed_on', 'known-good', 'unavailable', 'product', 'account', 'latency', 'cost', 'flash', 'scheduler'):
    assert phrase in s, phrase
PY
  [ "$status" -eq 0 ]
}

@test "locked maintenance fixture preserves public checks" {
  local fixture="$BATS_TMPDIR/locked"
  mkdir -p "$fixture/tests/scripts/helpers" "$fixture/.agents/rules" "$fixture/docs/runbooks"
  cp "$REPO_ROOT/tests/scripts/agent-routing.bats" "$fixture/tests/scripts/"
  cp "$REPO_ROOT/tests/scripts/helpers/test_helper.bash" "$REPO_ROOT/tests/scripts/helpers/agent_routing.bash" "$fixture/tests/scripts/helpers/"
  cp "$REPO_ROOT/AGENTS.md" "$fixture/AGENTS.md"
  cp "$REPO_ROOT/.agents/rules/model-routing.md" "$fixture/.agents/rules/"
  printf '\0GITCRYPT\0\377synthetic' > "$fixture/docs/runbooks/agent-model-maintenance.md"
  # Bootstrap nested Bats even when a parallel runner loses exported Bash functions.
  run env -u 'BASH_FUNC_bats_readlinkf%%' "$BATS_ROOT/bin/bats" --print-output-on-failure "$fixture/tests/scripts/agent-routing.bats" --filter '^maintenance'
  if [ "$status" -ne 0 ]; then
    printf 'Nested maintenance checks exited %s:\n%s\n' "$status" "$output" >&2
  fi
  [ "$status" -eq 0 ]
  printf 'missing public import\n' > "$fixture/.agents/rules/model-routing.md"
  run env -u 'BASH_FUNC_bats_readlinkf%%' "$BATS_ROOT/bin/bats" --print-output-on-failure "$fixture/tests/scripts/agent-routing.bats" --filter '^maintenance'
  [ "$status" -eq 1 ]
  cp "$REPO_ROOT/.agents/rules/model-routing.md" "$fixture/.agents/rules/"
  printf 'incomplete policy\n' > "$fixture/docs/runbooks/agent-model-maintenance.md"
  run env -u 'BASH_FUNC_bats_readlinkf%%' "$BATS_ROOT/bin/bats" --print-output-on-failure "$fixture/tests/scripts/agent-routing.bats" --filter '^maintenance'
  [ "$status" -eq 1 ]
}

@test "routing validates complete real repository configuration offline" {
  run uv run --quiet --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "synthetic trial fixture is independent and records only explicit fake calls" {
  run make_routing_trial_fixture "$BATS_TMPDIR/trial" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  fixture="$BATS_TMPDIR/trial/worktree"
  [ -f "$fixture/.agent-models.json" ]
  [ ! -e "$fixture/secrets" ]
  [ "$(cd "$(git -C "$fixture" rev-parse --git-common-dir)" && pwd -P)" = "$(cd "$BATS_TMPDIR/trial/repo/.git" && pwd -P)" ]
  [ ! -e "$fixture/attempts.log" ]
  run "$fixture/bin/provider-error" worker-unavailable
  [ "$status" -eq 1 ]
  [[ "$output" == *worker-unavailable* ]] || false
  run "$fixture/bin/provider-error" coordinator-unavailable
  [ "$status" -eq 1 ]
  [[ "$output" == *coordinator-unavailable* ]] || false
  [ "$(wc -l < "$fixture/dispatch.log" | tr -d ' ')" -eq 2 ]
  [ ! -e "$fixture/attempts.log" ]
  "$fixture/bin/tofu" synthetic-1
  [ "$(cat "$fixture/attempts.log")" = 'tofu synthetic-1' ]
  "$fixture/bin/ansible-playbook" synthetic-2
  [ "$(tail -n 1 "$fixture/attempts.log")" = 'ansible-playbook synthetic-2' ]
  [ -f "$fixture/personal-config/settings.json" ]
}

@test "trial fixture isolates Git configuration and honors its local hooks" {
  mkdir -p "$BATS_TMPDIR/external-hooks"
  printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$BATS_TMPDIR/external-hook-ran" > "$BATS_TMPDIR/external-hooks/pre-commit"
  chmod +x "$BATS_TMPDIR/external-hooks/pre-commit"
  printf '[core]\n hooksPath = %s\n[commit]\n gpgsign = true\n' "$BATS_TMPDIR/external-hooks" > "$BATS_TMPDIR/global.gitconfig"
  export GIT_CONFIG_GLOBAL="$BATS_TMPDIR/global.gitconfig"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$BATS_TMPDIR/external-hooks"
  run make_routing_trial_fixture "$BATS_TMPDIR/trial-isolated" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TMPDIR/external-hook-ran" ]
  run grep -F 'core.hooksPath' "$REPO_ROOT/tests/scripts/helpers/agent_routing.bash"
  [ "$status" -eq 1 ]
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_GLOBAL
  repo="$BATS_TMPDIR/trial-isolated/repo"
  mkdir -p "$repo/.git/hooks"
  printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$BATS_TMPDIR/local-hook-ran" > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
  run env -i PATH="$PATH" HOME="$BATS_TMPDIR/trial-isolated/git-home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit --allow-empty -m check
  [ "$status" -ne 0 ]
  [ -e "$BATS_TMPDIR/local-hook-ran" ]
}

@test "routing accepts only the reviewed root App wrapper exclusions" {
  jq '.sandbox = {excludedCommands:["scripts/agent-gh.sh *","scripts/agent-git.sh *"]}' \
    "$BATS_TMPDIR/.claude/settings.json" > "$BATS_TMPDIR/settings.json"
  mv "$BATS_TMPDIR/settings.json" "$BATS_TMPDIR/.claude/settings.json"
  run validate
  [ "$status" -eq 0 ]
}

@test "routing still rejects broader or nested sandbox exceptions" {
  local config
  for config in '{"excludedCommands":["scripts/agent-gh.sh *","scripts/agent-git.sh *","bash *"]}' \
    '{"excludedCommands":["*"]}' \
    '{"excludedCommands":["scripts/agent-gh.sh *","scripts/agent-git.sh *"],"enabled":false}'; do
    jq --argjson sandbox "$config" '.sandbox=$sandbox' "$BATS_TMPDIR/.claude/settings.json" > "$BATS_TMPDIR/settings.json"
    mv "$BATS_TMPDIR/settings.json" "$BATS_TMPDIR/.claude/settings.json"
    run validate
    [ "$status" -eq 1 ] || return 1
    [[ "$output" == *unsafe_settings* ]] || return 1
  done
  jq 'del(.sandbox) | .env={sandbox:{excludedCommands:["scripts/agent-gh.sh *","scripts/agent-git.sh *"]}}' \
    "$BATS_TMPDIR/.claude/settings.json" > "$BATS_TMPDIR/settings.json"
  mv "$BATS_TMPDIR/settings.json" "$BATS_TMPDIR/.claude/settings.json"
  run validate
  [ "$status" -eq 1 ]
  [[ "$output" == *unsafe_settings* ]] || false
}

@test "routing rejects permission bypass with otherwise approved App exclusions" {
  jq '.sandbox={excludedCommands:["scripts/agent-gh.sh *","scripts/agent-git.sh *"]} | .permissions={defaultMode:"bypassPermissions"}' \
    "$BATS_TMPDIR/.claude/settings.json" > "$BATS_TMPDIR/settings.json"
  mv "$BATS_TMPDIR/settings.json" "$BATS_TMPDIR/.claude/settings.json"
  run validate
  [ "$status" -eq 1 ]
  [[ "$output" == *unsafe_permissions* ]] || false
}
