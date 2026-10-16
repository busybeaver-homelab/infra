# Install Antigravity Superpowers Profile

This package is a standalone Antigravity profile. It does not modify the original Superpowers source workflows.

## Prerequisites

- Antigravity environment installed
- Shell access
- This repository available locally

## Install

From your project root:

```bash
npx --yes antigravity-superpowers@0.1.0 init
```

Or manually:

```bash
mkdir -p .agent
cp -R /path/to/antigravity-superpowers-cli/templates/.agent/* .agent/
```

If your project already has `.agent/skills`, merge carefully and keep the versions you want.

> **Note:** `.agent/` is managed by `antigravity-superpowers@0.1.0`. Domain skills in `.agents/skills/` are managed separately via `npx --yes skills@1.7.2` and verified against `skills-lock.json` by `scripts/verify-skills-lock.sh`.

## What Gets Installed

- `.agent/AGENTS.md`
- `.agent/skills/*`
- `.agent/workflows/*`
- `.agent/agents/*`
- `.agent/tests/*`

Runtime tracking file:

- `docs/plans/task.md` in the target project root (created at runtime by skill flow, list-only table)

## Verify Profile

From your target project root:

```bash
bash .agent/tests/run-tests.sh
```

Expected result: all checks pass with zero failures.

## Usage Notes

- This profile uses strict single-flow task execution.
- Generic coding subagents are intentionally not used.
- Browser automation can use `browser_subagent` when needed.
- Skill references are local to `.agent/skills`.

## Update

Re-run the CLI init with `--force` to update, then rerun validation:

```bash
bash .agent/tests/run-tests.sh
```
