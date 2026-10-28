#!/usr/bin/env bash
# Codex decision adapter: reuse the classifier, never emit unsupported "ask".
set -Eeuo pipefail
set +x

deny() {
  printf 'Codex credential guard: %s\n' "$1" >&2
  exit 2
}

trap 'deny "Evaluation failed; refusing the call."' ERR
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
classifier="${repo_root}/.claude/hooks/agent-credential-guard.sh"
[[ -f "$classifier" ]] || deny 'Shared classifier is unavailable; refusing the call.'

# The JSON input flows to the classifier on stdin. Only its decision output is
# captured, never the incoming command or a credential. Do not echo it on errors.
if decision="$(bash "$classifier" --all-tofu-gated)"; then
  if [[ -z "$decision" ]]; then
    exit 0
  fi
else
  deny 'Shared policy denied the call or failed; refusing the call.'
fi

# Codex currently fails open on PreToolUse ask. Translate a well-formed ask to a
# blocking exit instead; the owner runs gated operations outside the agent.
if printf '%s' "$decision" | python3 -c '
import json
import sys
try:
    output = json.load(sys.stdin)["hookSpecificOutput"]
    valid = (
        output.get("hookEventName") == "PreToolUse"
        and output.get("permissionDecision") == "ask"
        and isinstance(output.get("permissionDecisionReason"), str)
        and bool(output["permissionDecisionReason"])
    )
except (ValueError, KeyError, TypeError, AttributeError):
    valid = False
sys.exit(0 if valid else 1)
' 2>/dev/null; then
  deny 'The owner must run this operation directly; Codex cannot request approval from this hook.'
else
  deny 'Unexpected policy output; refusing the call.'
fi
