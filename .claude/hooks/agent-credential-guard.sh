#!/usr/bin/env bash
# PreToolUse guard. Requires Python 3; input is parsed as data, never evaluated.
set -Eeuo pipefail
set +x

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'Agent credential guard: Python 3 is required; refusing the call.' >&2
  exit 2
fi

# Keep hook JSON on fd 3; stdin supplies the fixed program, not incoming code.
if python3 - "$@" 3<&0 <<'PY'
import json
import os
import re
import shlex
import sys


def deny(reason):
    print("Agent credential guard: " + reason, file=sys.stderr)
    raise SystemExit(2)


def ask(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "ask",
        "permissionDecisionReason": reason,
    }}))
    raise SystemExit(0)


# Reviewed read-only tool names. Unknown tools fail closed, including new
# mutation verbs and connectors whose method-dispatch tools have mixed effects.
READ_TOOLS = {
    "get_me", "get_file_contents", "get_commit", "list_commits", "list_branches",
    "list_tags", "get_tag", "get_release_by_tag", "get_latest_release",
    "list_releases", "issue_read", "list_issues", "pull_request_read",
    "list_pull_requests", "get_pull_request", "get_pull_request_files",
    "get_pull_request_status", "get_pull_request_reviews", "get_pull_request_comments",
    "search_code", "search_issues", "search_pull_requests", "search_repositories",
    "search_users", "actions_get", "actions_list", "get_job_logs",
    "get_code_quality_finding", "get_code_scanning_alert",
}

if sys.argv[1:] not in ([], ["--all-tofu-gated"]):
    deny("Unsupported classifier options.")

try:
    with os.fdopen(3) as stream:
        payload = json.load(stream)
    tool = payload["tool_name"]
    if not isinstance(tool, str):
        raise ValueError
    if tool != "Bash":
        if ("github" in tool.lower() or "octocode" in tool.lower()) and tool.rsplit("__", 1)[-1] not in READ_TOOLS:
            deny("GitHub writes and unclassified tools must use the App wrappers.")
        raise SystemExit(0)
    command = payload["tool_input"]["command"]
    cwd = payload["cwd"]
    if not isinstance(command, str) or not command.strip():
        raise ValueError
    if not isinstance(cwd, str) or not os.path.isabs(cwd):
        raise ValueError
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    words = list(lexer)
    if not words:
        raise ValueError
except (ValueError, TypeError, KeyError, OSError):
    deny("Invalid hook input; refusing the call.")

wrappers = {"scripts/agent-gh.sh", "scripts/agent-git.sh"}
if any(wrapper in command for wrapper in wrappers):
    # Deliberately narrower than shell grammar. Even quoted expansion/control
    # characters are rejected; put complex PR text in a body file instead.
    if words[0] not in wrappers or not command.startswith(words[0] + " "):
        deny("Invoke the App wrapper as the literal first word.")
    if re.search(r"[;&|<>$`\\\n\r#*?\[\]{}~]", command):
        deny("App wrapper calls must be a single literal command without expansion or redirection.")
    raise SystemExit(0)

# Shell substitutions and compound commands obscure executable/directory
# boundaries. Refuse them rather than pretending shlex is a shell parser.
if re.search(r"\b(gh|git|sops|tofu|security|git-crypt)\b", command) and re.search(
    r"[;&|<>$`\n\r]", command
):
    deny("Submit each sensitive operation as one literal command without shell composition.")

# Inspect normalized tokens as well as spelling: quoting or backslash escapes
# must not turn a direct gh invocation into an allowed command.
bases = [os.path.basename(word) for word in words]
if "gh" in bases or re.search(r"(?:^|[\s`])gh(?:[\s`]|$)", command):
    deny("Use scripts/agent-gh.sh for GitHub CLI access.")
if "git" in bases and any(word in words for word in (
    "push", "fetch", "pull", "clone", "ls-remote", "remote-https", "remote-http"
)):
    deny("Use scripts/agent-git.sh for Git network access.")
if "git" in bases and any("alias." in word for word in words):
    deny("Inline Git aliases may bypass App transport; use explicit local Git commands.")
if "git" in bases and ("credential" in words or any(
    "credential." in word or "http." in word and "extraheader" in word.lower()
    for word in words
)):
    deny("Owner Git credentials and helpers are unavailable to agents.")
if "git" in bases:
    args = words[bases.index("git") + 1:]
    while args and args[0].startswith("-"):
        option = args.pop(0)
        if option in {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}:
            if not args:
                deny("Incomplete Git options.")
            args.pop(0)
    local_git = {
        "add", "am", "apply", "archive", "bisect", "blame", "branch", "check-attr",
        "check-ignore", "checkout", "cherry", "cherry-pick", "clean", "commit",
        "config", "describe", "diff", "diff-files", "diff-index", "diff-tree",
        "for-each-ref", "format-patch", "fsck", "grep", "hash-object", "init",
        "log", "ls-files", "ls-tree", "merge", "merge-base", "notes", "rebase",
        "reflog", "reset", "restore", "rev-list", "rev-parse", "revert", "rm",
        "shortlog", "show", "show-ref", "sparse-checkout", "stash", "status",
        "switch", "symbolic-ref", "tag", "update-index", "update-ref",
        "verify-commit", "verify-tag", "version", "worktree",
    }
    if args and args[0] not in local_git:
        deny("Unknown Git commands and aliases are unavailable; use explicit local commands.")
    if any(arg.startswith("--remote") for arg in args):
        deny("Remote Git access requires the App Git wrapper.")
if "sops" in bases and any(word in words for word in ("-d", "--decrypt", "--decrypt=true", "decrypt", "--extract")) or (
    "sops" in bases and any(word.startswith("--extract=") for word in words)
):
    deny("Direct secret getters are forbidden; use repository consumers.")
if "git-crypt" in bases and "export-key" in words:
    deny("Secret key export is forbidden.")
if any(".config/gh" in word or "Library/Application Support/gh" in word for word in words):
    deny("Reading the owner's GitHub CLI configuration is forbidden.")
if "security" in bases and any(word.startswith("find-") and word.endswith("-password") for word in words):
    deny("Reading password credentials from Keychain is forbidden.")

# Compound/indirect sensitive commands cannot be safely classified as local.
# This is a guardrail for normal agent calls, not a shell isolation boundary.
if re.search(r"\b(gh|git|sops|tofu|security)\b", command) and any(
    base in {"bash", "sh", "zsh", "eval"} for base in bases
):
    deny("Submit the sensitive command directly so the guard can inspect it.")

if "tofu" in bases:
    if re.search(r"[$`\\]", command):
        deny("Submit literal OpenTofu arguments so this invocation can be reviewed.")
    index = bases.index("tofu")
    args = words[index + 1:]
    if any(arg in {"show", "output"} for arg in args) or (
        "state" in args and "pull" in args
    ):
        deny("State and plan dumps are forbidden.")
    if any(arg in {"apply", "destroy", "import"} for arg in args) or (
        "state" in args and any(arg in {"mv", "rm"} for arg in args)
    ):
        ask("R2-GOV-05: confirm the exact effect of this infrastructure mutation for this invocation.")
    target = os.path.realpath(cwd)
    for arg in args:
        if arg.startswith("-chdir="):
            target = os.path.realpath(os.path.join(cwd, arg.split("=", 1)[1]))
    github = sys.argv[1:] == ["--all-tofu-gated"] or (
        target.endswith("/infrastructure/github") or "/infrastructure/github/" in target
    )
    compound = bool(re.search(r"[;&|`$\n\r]", command))
    if "plan" in args and (github or compound):
        ask("R2-GOV-05: GitHub planning reads owner credentials and may run external programs; confirm this invocation.")
    if github and "init" in args and (
        "-backend=false" not in args or any(arg.startswith("-backend=") and arg != "-backend=false" for arg in args)
    ):
        ask("R2-GOV-05: confirm GitHub backend initialization; only init -backend=false is unattended.")
    if github and not any(arg in {"test", "validate"} for arg in args) and "init" not in args:
        ask("R2-GOV-05: only mock tests, validation and init -backend=false are unattended in infrastructure/github.")
PY
then
  exit 0
else
  result=$?
  if [[ "$result" -ne 2 ]]; then
    printf '%s\n' 'Agent credential guard: evaluation failed; refusing the call.' >&2
  fi
  exit 2
fi
