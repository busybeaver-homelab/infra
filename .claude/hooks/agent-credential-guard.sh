#!/usr/bin/env bash
# PreToolUse guard. Requires Python 3; input is parsed as data, never evaluated.
set -Eeuo pipefail
set +x

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'Agent credential guard: Python 3 is required; refusing the call.' >&2
  exit 2
fi
guard_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# Keep hook JSON on fd 3; stdin supplies the fixed program, not incoming code.
# -I keeps the session directory and PYTHON* variables out of module lookup.
if AGENT_GUARD_ROOT="$guard_root" python3 -I - "$@" 3<&0 <<'PY'
import glob
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
CREDENTIAL_PATHS = re.compile(
    r"(?:\.config|Library/Application Support)/gh(?:/|$)|(?:^|[/=@])\.(?:ssh|gnupg)(?:/|$)"
    r"|\.git-credentials|\.netrc|\.config/sops"
)
WRAPPER_PATHS = re.compile(r"keys\.txt|(?:^|[=@]|\./)secrets(?:/|$)|(?:^|[/=@])\.git(?:/|$)")
INTERPRETERS = re.compile(
    r"(?:ba|z|da|k|fi|c|tc)?sh|eval|python[0-9.]*|perl|ruby|node|osascript|g?awk|pwsh|tclsh"
)
# Git settings that run programs, redirect hooks or include other config.
GIT_EXEC_KEYS = re.compile(
    r"(?:core\.(?:hookspath|pager|editor|sshcommand|fsmonitor|askpass|gitproxy)"
    r"|sequence\.editor|diff\.external|diff\..+\.(?:textconv|command)|filter\..+"
    r"|merge\..+\.driver|gpg(?:\..+)?\.program|include\.path|includeif\..+"
    r"|pager\..+|interactive\.difffilter|uploadpack\..+|receivepack\..+|trailer\..+\.(?:cmd|command)"
    r"|gpg\.ssh\.defaultkeycommand|core\.alternaterefscommand|init\.templatedir)(?:=.*)?"
)
GIT_EXEC_ENV = re.compile(
    r"(?:GIT_(?:EXTERNAL_DIFF|SSH|SSH_COMMAND|ASKPASS|EDITOR|SEQUENCE_EDITOR|EXEC_PATH"
    r"|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\w+|CONFIG_VALUE_\w+|CONFIG_GLOBAL"
    r"|CONFIG_SYSTEM|TEMPLATE_DIR)|LEFTHOOK\w*)=.*"
)
# Repository entry points that consume production credentials (R2-GOV-05).
GATED_SCRIPTS = {
    "sync-github-repo-settings.sh", "sync-ops-secrets.sh", "sync-cloudflare-budget-alert.sh",
    "drift.sh", "drift-cloudflare.sh", "drift-dns.sh", "bootstrap-state-backend.sh",
    "generate-inventory.sh", "get-tofu-restic-vars.sh", "get-tofu-robot-vars.sh",
}
GATED_TASKS = re.compile(r"(?:github:sync|sync:|drift(?::|$)|ansible:inventory).*")
ANSIBLE_INFO = {"--syntax-check", "--list-tasks", "--list-tags", "--list-hosts", "--version", "-h", "--help"}
SENSITIVE = re.compile(r"(?<![\w-])(?:gh|git|sops|tofu|security|git-crypt|ansible|ansible-playbook)(?![\w-])")
EXECUTABLES = {"gh", "git", "sops", "tofu", "security", "git-crypt", "ansible", "ansible-playbook", "mise"}
# Options whose values a program executes, and shell grouping words.
EXEC_OPTIONS = {"-x", "--exec", "-c", "--config-env", "-e", "-E", "--eval", "-p", "--print", "run", "-exec", "--command"}
GROUPING = {"(", ")", "!", "{", "}", "coproc"}
# Commands that may name a wrapper path without running it.
MENTION_SAFE = {
    "git", "shellcheck", "shfmt", "cat", "head", "tail", "wc", "ls", "stat", "diff", "grep", "rg",
    "bats", "file", "oxfmt", "actionlint", "trufflehog",
}
LAUNCHERS = {
    "env", "command", "exec", "nohup", "sudo", "time", "xargs", "nice", "timeout", "stdbuf",
    "caffeinate", "ionice", "taskset", "unbuffer",
}
GIT_SAFE_GLOBALS = {
    "--no-pager", "-P", "-p", "--paginate", "--no-replace-objects", "--bare", "--literal-pathspecs",
    "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs", "--no-optional-locks",
    "--no-advice", "--version", "--help",
}
# Environment that git, its pager or hooks may consult; anything else is refused.
GIT_SAFE_ENV = re.compile(r"(?:(?:GIT_PAGER|PAGER)=cat|(?:LC_ALL|LANG|TZ|GIT_AUTHOR_DATE|GIT_COMMITTER_DATE)=.*)")
SOPS_SUBCOMMANDS = {"updatekeys", "encrypt", "rotate", "filestatus", "set", "unset", "version", "help"}
SOPS_FLAGS = {"-e", "--encrypt", "-r", "--rotate", "--version", "-v", "-h", "--help"}

if sys.argv[1:] not in ([], ["--all-tofu-gated"]):
    deny("Unsupported classifier options.")
all_tofu_gated = sys.argv[1:] == ["--all-tofu-gated"]
guard_root = os.environ.get("AGENT_GUARD_ROOT", "")


def split(text):
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


try:
    with os.fdopen(3) as stream:
        payload = json.load(stream)
    tool = payload["tool_name"]
    if not isinstance(tool, str):
        raise ValueError
    if tool != "Bash":
        lowered = tool.lower()
        server = lowered.split("__")[1] if lowered.startswith("mcp__") and lowered.count("__") >= 2 else lowered
        github_tool = "github" in lowered or "octocode" in lowered or re.search(r"(?:^|[_-])gh(?:[_-]|$)", server)
        if github_tool and tool.rsplit("__", 1)[-1] not in READ_TOOLS:
            deny("GitHub writes and unclassified tools must use the App wrappers.")
        raise SystemExit(0)
    command = payload["tool_input"]["command"]
    cwd = payload["cwd"]
    if not isinstance(command, str) or not command.strip():
        raise ValueError
    if not isinstance(cwd, str) or not os.path.isabs(cwd):
        raise ValueError
    if not os.path.isabs(guard_root):
        raise ValueError
    words = split(command)
    if not words:
        raise ValueError
    # Quoted arguments can carry whole commands (rebase -x, pager settings).
    # Values a program executes are inspected token by token; other text
    # (commit messages) only when it starts with a sensitive executable.
    segments, pending = [words], [words]
    while pending:
        if len(segments) >= 64:
            raise ValueError
        previous = ""
        for word in pending.pop():
            executed = previous in EXEC_OPTIONS or re.match(r"(?:--exec|[A-Za-z_][\w.]*)=", word)
            previous = word
            for text in (word, word.split("=", 1)[-1]):
                if not re.search(r"\s", text):
                    continue
                try:
                    inner = split(text)
                except ValueError:
                    inner = [re.sub(r"[\"'\\]", "", w) for w in text.split()]
                names = {os.path.basename(w) for w in inner}
                start = [
                    os.path.basename(w) for w in inner
                    if "=" not in w.split("/")[0] and w not in LAUNCHERS | GROUPING
                    and not re.fullmatch(r"-\S*|[0-9.]+[smhd]?", w)
                ][:1]
                if (executed or start and INTERPRETERS.fullmatch(start[0])) and SENSITIVE.search(text) and any(
                    INTERPRETERS.fullmatch(name) for name in names
                ):
                    deny("Submit the sensitive command directly so the guard can inspect it.")
                if inner and inner not in segments and (
                    start and start[0] in EXECUTABLES | GATED_SCRIPTS
                    or executed and names & (EXECUTABLES | GATED_SCRIPTS)
                ):
                    segments.append([w for w in inner if w not in GROUPING])
                    pending.append(inner)
except (ValueError, TypeError, KeyError, OSError):
    deny("Invalid hook input; refusing the call.")

if any(CREDENTIAL_PATHS.search(word) for word in words):
    deny("Owner credential files are unavailable to agents.")

wrappers = {"scripts/agent-gh.sh", "scripts/agent-git.sh"}
wrapper_names = {os.path.basename(wrapper) for wrapper in wrappers}
# Paths that merely mention a wrapper (git add, shellcheck) are ordinary
# commands; anything that could execute one must be the literal wrapper call.
runner = list(words)
while runner and runner[0] in {"mise", "exec", "--", "uv", "run", "--locked"}:
    runner.pop(0)
if any(name in command for name in wrapper_names) and (
    words[0] in wrappers
    or re.search(r"[;&|<>$`\n\r]", command)
    or not runner
    or os.path.basename(runner[0]) not in MENTION_SAFE
):
    # Deliberately narrower than shell grammar. Even quoted expansion/control
    # characters are rejected; put complex PR text in a body file instead.
    if words[0] not in wrappers or not command.startswith(words[0] + " "):
        deny("Invoke the App wrapper as the literal first word.")
    if re.search(r"[;&|<>$`\\\n\r#*?\[\]{}~]", command):
        deny("App wrapper calls must be a single literal command without expansion or redirection.")
    if any(WRAPPER_PATHS.search(word) for word in words):
        deny("App wrappers cannot read secrets, keys or Git internals.")
    raise SystemExit(0)

# Shell substitutions and compound commands obscure executable/directory
# boundaries. Refuse them rather than pretending shlex is a shell parser.
if SENSITIVE.search(command) and re.search(r"[;&|<>$`\n\r]", command):
    deny("Submit each sensitive operation as one literal command without shell composition.")

# Inline interpreter code cannot be classified; refuse it near sensitive tools.
bases = [os.path.basename(word) for word in words]
if SENSITIVE.search(command) and any(INTERPRETERS.fullmatch(base) for base in bases):
    deny("Submit the sensitive command directly so the guard can inspect it.")



def github_module(path):
    if path.endswith("/infrastructure/github") or "/infrastructure/github/" in path:
        return True
    names = glob.glob(os.path.join(glob.escape(path), "*.tf")) + glob.glob(os.path.join(glob.escape(path), "*.tf.json"))
    for name in sorted(names)[:200]:
        if not os.path.isfile(name):
            continue
        try:
            with open(name, encoding="utf-8", errors="replace") as handle:
                if "integrations/github" in handle.read(1_000_000):
                    return True
        except OSError:
            return True
    return False


def mock_only(path, test_dir):
    root = glob.escape(path)
    files = glob.glob(os.path.join(root, "*.tftest.hcl")) + glob.glob(os.path.join(root, glob.escape(test_dir), "*.tftest.hcl"))
    for name in files[:200]:
        if not os.path.isfile(name):
            return False
        try:
            with open(name, encoding="utf-8", errors="replace") as handle:
                text = handle.read(1_000_000)
        except OSError:
            return False
        if not re.search(r'^\s*mock_provider\s+"github"', text, re.M) or re.search(r'^\s*provider\s+"github"', text, re.M):
            return False
    return True


# Collect approvals so a deny in any nested command still wins.
approvals = []


def classify(words):
    bases = [os.path.basename(word) for word in words]
    if "gh" in bases:
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
        if any(
            "=" in word.split("/")[0] and not GIT_SAFE_ENV.fullmatch(word) for word in words[:bases.index("git")]
        ):
            deny("Git and hook environment overrides are unavailable to agents.")
        args = words[bases.index("git") + 1:]
        while args and args[0].startswith("-"):
            option = args.pop(0)
            if option in {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}:
                if not args:
                    deny("Incomplete Git options.")
                value = args.pop(0)
            elif option.startswith(("--git-dir=", "--work-tree=", "--namespace=", "--config-env=")):
                option, value = option.split("=", 1)
            elif option in GIT_SAFE_GLOBALS:
                continue
            else:
                deny("Unknown Git global options are unavailable.")
            if option in {"-c", "--config-env"} and GIT_EXEC_KEYS.fullmatch(value.lower()):
                deny("Git settings that run programs or redirect hooks are unavailable.")
        local_git = {
            "add", "am", "apply", "archive", "bisect", "blame", "branch", "check-attr",
            "check-ignore", "checkout", "cherry", "cherry-pick", "clean", "commit",
            "config", "describe", "diff", "diff-files", "diff-index", "diff-tree",
            "for-each-ref", "format-patch", "fsck", "grep", "hash-object", "init",
            "log", "ls-files", "ls-tree", "merge", "merge-base", "notes", "rebase",
            "reflog", "reset", "restore", "rev-list", "rev-parse", "revert", "rm",
            "shortlog", "show", "show-ref", "sparse-checkout", "stash", "status",
            "switch", "symbolic-ref", "tag", "update-index", "update-ref",
            "verify-commit", "verify-tag", "version", "worktree", "mv", "cat-file", "range-diff", "remote",
        }
        if args and args[0] not in local_git:
            deny("Unknown Git commands and aliases are unavailable; use explicit local commands.")
        if any(arg.startswith("--remote") for arg in args):
            deny("Remote Git access requires the App Git wrapper.")
        if args and args[0] == "remote" and not (
            set(args[1:]) <= {"-v", "--verbose"} or args[1:2] == ["get-url"]
        ):
            deny("Only read-only remote listing is available; network Git uses the App wrapper.")
        if args and args[0] == "config" and any(
            GIT_EXEC_KEYS.fullmatch(arg.lower()) for arg in args[1:]
        ) and not any(arg in {"--get", "--get-all", "--get-regexp", "-l", "--list", "get", "list"} for arg in args[:2]):
            deny("Git settings that run programs or redirect hooks are unavailable.")
        if any(len(arg.split("=")[0]) >= 5 and "--no-verify".startswith(arg.split("=")[0]) for arg in args):
            deny("Git hooks are mandatory; --no-verify is forbidden.")
        if args and args[0] == "commit":
            skip = False
            for arg in args[1:]:
                if skip:
                    skip = False
                    continue
                if arg in {
                    "--message", "--file", "--reuse-message", "--reedit-message", "--template", "--author",
                    "--date", "--fixup", "--squash", "--trailer", "--cleanup",
                }:
                    skip = True
                    continue
                if not re.fullmatch(r"-[^-].*", arg):
                    continue
                # Short options stop at the first one that takes a value;
                # a value-taking letter at the end consumes the next word.
                for position, letter in enumerate(arg[1:], 1):
                    if letter == "n":
                        deny("Git hooks are mandatory; --no-verify is forbidden.")
                    if letter in "mFcCtS":
                        skip = letter != "S" and position == len(arg) - 1
                        break
    if "sops" in bases:
        sops_args = words[bases.index("sops") + 1:]
        if any(re.fullmatch(r"(?:-{1,2}(?:d|decrypt|extract)|decrypt|exec-env|exec-file|edit)(?:=.*)?", word) for word in sops_args):
            deny("Direct secret getters are forbidden; use repository consumers.")
        if not sops_args or sops_args[0] not in SOPS_SUBCOMMANDS | SOPS_FLAGS:
            deny("sops must start with an explicit non-decrypting action; a bare file opens a decrypting editor.")
    if "git-crypt" in bases and "export-key" in words:
        deny("Secret key export is forbidden.")
    if "security" in bases and any(
        word.startswith("find-") and word.endswith("-password") or word in {"dump-keychain", "export"} for word in words
    ):
        deny("Reading password credentials from Keychain is forbidden.")
    if "mise" in bases and any(re.fullmatch(r"secret:\S*:get", word) for word in words):
        deny("Direct secret getters are forbidden; use repository consumers.")

    gated = None
    if "mise" in bases and any(GATED_TASKS.fullmatch(word) for word in words):
        gated = "R2-GOV-05: this task reads production credentials; confirm this invocation."
    if GATED_SCRIPTS.intersection(bases):
        gated = "R2-GOV-05: this script reads production credentials; confirm this invocation."
    if {"ansible", "ansible-playbook"}.intersection(bases) and not ANSIBLE_INFO.intersection(words):
        gated = "R2-GOV-05: confirm this Ansible run against its inventory for this invocation."

    if "tofu" in bases:
        if re.search(r"[$`\\]", command):
            deny("Submit literal OpenTofu arguments so this invocation can be reviewed.")
        index = bases.index("tofu")
        args = words[index + 1:]
        if any(arg in {"show", "output"} for arg in args) or (
            "state" in args and "pull" in args
        ):
            deny("State and plan dumps are forbidden.")
        if any(arg in {"apply", "destroy", "import", "refresh", "taint", "untaint", "force-unlock", "console"} for arg in args) or (
            "state" in args and any(arg in {"mv", "rm", "push", "replace-provider"} for arg in args)
        ) or ("workspace" in args and "delete" in args):
            approvals.append("R2-GOV-05: confirm the exact effect of this infrastructure mutation for this invocation.")
        # Wrappers such as mise -C change the directory OpenTofu starts in.
        target = cwd
        prefix = words[:index]
        for position, word in enumerate(prefix):
            value = None
            if word in {"-C", "--cd", "--chdir", "--directory"} and position + 1 < len(prefix):
                value = prefix[position + 1]
            elif word.startswith(("--cd=", "--chdir=", "--directory=")):
                value = word.split("=", 1)[1]
            if value is not None:
                if value.startswith("~"):
                    deny("Use an explicit OpenTofu directory without home expansion.")
                target = os.path.join(target, value)
        test_dir = "tests"
        for position, arg in enumerate(args):
            if arg.startswith("-chdir="):
                if arg.split("=", 1)[1].startswith("~"):
                    deny("Use an explicit OpenTofu directory without home expansion.")
                target = os.path.join(target, arg.split("=", 1)[1])
            elif arg.startswith("-test-directory="):
                test_dir = arg.split("=", 1)[1]
            elif arg == "-test-directory" and position + 1 < len(args):
                test_dir = args[position + 1]
        target = os.path.realpath(target)
        github = all_tofu_gated or github_module(target)
        subcommand = next((arg for arg in args if not arg.startswith("-")), "")
        compound = bool(re.search(r"[;&|`$\n\r]", command))
        if subcommand == "plan" and (github or compound):
            approvals.append("R2-GOV-05: GitHub planning reads owner credentials and may run external programs; confirm this invocation.")
        if github and subcommand == "init" and (
            "-backend=false" not in args or any(arg.startswith("-backend=") and arg != "-backend=false" for arg in args)
        ):
            approvals.append("R2-GOV-05: confirm GitHub backend initialization; only init -backend=false is unattended.")
        if github and subcommand == "test":
            reviewed = [target] if github_module(target) else []
            if all_tofu_gated:
                reviewed.append(os.path.join(guard_root, "infrastructure/github"))
            if not all(mock_only(path, test_dir) for path in reviewed):
                approvals.append("R2-GOV-05: GitHub tests without mock providers use owner credentials; confirm this invocation.")
        if github and subcommand not in {"fmt", "validate", "version", "test", "init"}:
            approvals.append("R2-GOV-05: only formatting, mock tests, validation and init -backend=false are unattended in infrastructure/github.")
    if gated:
        approvals.append(gated)


for segment in segments:
    classify(segment)
if approvals:
    ask(approvals[0])
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
