#!/usr/bin/env bats
load helpers/test_helper
load helpers/agent_routing
setup() { setup_tmpdir; make_routing_fixture; }
teardown() { teardown_tmpdir; }
validate() { uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-10-28; }
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
@test "routing rejects unsupported effort and worker inherit" { sed -i.bak 's/model = "gpt-6-luna"/model = "inherit"/; s/medium/extreme/' "$BATS_TMPDIR/.codex/agents/routing-simple.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *model_mismatch* ]]; }
@test "routing rejects reviewer editing tools" { sed -i.bak 's/Read, Grep, Glob/Read, Edit/' "$BATS_TMPDIR/.claude/agents/routing-reviewer.md"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_permissions* ]]; }
@test "routing rejects unknown role files" { cp "$BATS_TMPDIR/.codex/agents/routing-simple.toml" "$BATS_TMPDIR/.codex/agents/routing-extra.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *invalid_roles* ]]; }
@test "routing rejects future reviews and invalid dates" { run uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of 2026-10-27; [ "$status" -eq 2 ]; [[ "$output" == *invalid_input* ]]; run uv run --locked python "$SCRIPTS_DIR/check-agent-routing.py" --root "$BATS_TMPDIR" --as-of invalid; [ "$status" -eq 2 ]; }
@test "routing rejects blanket forced model" { printf '\nforced_subagent_model = "gpt-6-luna"\n' >> "$BATS_TMPDIR/.codex/config.toml"; run validate; [ "$status" -eq 1 ]; [[ "$output" == *unsafe_settings* ]]; }
