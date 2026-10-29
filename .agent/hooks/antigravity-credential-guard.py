#!/usr/bin/env python3
"""Translate native Antigravity calls into the shared credential policy."""

import json
import subprocess
import sys
from pathlib import Path


def deny(reason: str) -> dict[str, str]:
    return {"decision": "deny", "reason": reason}


def classify(payload: object) -> dict[str, str]:
    if not isinstance(payload, dict):
        return deny("Invalid hook input; refusing the call.")
    call = payload.get("toolCall")
    if not isinstance(call, dict):
        return deny("Invalid tool call; refusing the call.")
    name, args = call.get("name"), call.get("args")
    if not isinstance(name, str) or not name or not isinstance(args, dict):
        return deny("Invalid tool arguments; refusing the call.")
    if name == "manage_task" and args.get("Action") == "send_input":
        return deny(
            "Interactive task input is unavailable; submit commands separately."
        )
    canonical = {"tool_name": name, "tool_input": args}
    if name == "run_command":
        command, cwd = args.get("CommandLine"), args.get("Cwd")
        if (
            not isinstance(command, str)
            or not command.strip()
            or not isinstance(cwd, str)
            or not Path(cwd).is_absolute()
        ):
            return deny("A literal command and absolute Cwd are required.")
        canonical = {
            "tool_name": "Bash",
            "cwd": cwd,
            "tool_input": {"command": command},
        }
    else:
        # Some integrations expose single-underscore MCP names. Normalize only
        # known server prefixes, retaining the shared exact read-tool inventory.
        for server in ("github", "octocode"):
            prefix = f"mcp_{server}_"
            if name.startswith(prefix) and not name.startswith("mcp__"):
                canonical["tool_name"] = f"mcp__{server}__{name[len(prefix) :]}"
                break
    root = Path(__file__).resolve().parents[2]
    policy = root / ".claude/hooks/agent-credential-guard.sh"
    result = subprocess.run(
        ["bash", str(policy)],
        input=json.dumps(canonical),
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if result.returncode != 0:
        return deny("The shared credential policy denied the call or failed.")
    if not result.stdout.strip():
        return {"decision": "allow"}
    output = json.loads(result.stdout)["hookSpecificOutput"]
    if (
        output.get("hookEventName") == "PreToolUse"
        and output.get("permissionDecision") == "ask"
        and isinstance(output.get("permissionDecisionReason"), str)
        and output["permissionDecisionReason"]
    ):
        # Ordinary ask respects cached Always Allow grants; force_ask implements
        # the repository's one-confirmation-per-invocation rule instead.
        return {
            "decision": "force_ask",
            "reason": "R2-GOV-05: confirm the exact effect for this invocation.",
        }
    return deny("Unexpected policy output; refusing the call.")


def main() -> None:
    try:
        decision = classify(json.load(sys.stdin))
    except Exception:  # No incoming arguments or traceback may enter hook output.
        decision = deny("Policy evaluation failed; refusing the call.")
    print(json.dumps(decision))


if __name__ == "__main__":
    main()
