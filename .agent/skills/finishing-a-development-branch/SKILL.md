---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling chosen workflow.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests and Archive Task Tracker

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**If tests fail:**

```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Don't proceed to Step 2.

**Archive Task Tracker (if present):**

If an active ephemeral task tracker exists at `docs/plans/task.md`, archive it and commit before proceeding:

```bash
if [ -f "docs/plans/task.md" ]; then
  mkdir -p docs/plans/archive
  mv docs/plans/task.md "docs/plans/archive/task-$(date +%Y-%m-%d)-<topic>.md"
  git add "docs/plans/archive/task-$(date +%Y-%m-%d)-<topic>.md"
  git commit -m "docs(plans): archive task tracker for <topic>"
fi
```

**If tests pass and tracker is archived:** Continue to Step 2.

### Step 2: Determine Base Branch

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from main - is that correct?"

### Step 3: Present Options (or Execute Option 2 Automatically per `AGENTS.md` §4)

> **Repository Policy (`AGENTS.md` §4):** Unless the repository owner explicitly asked for a local merge (Option 1), keeping the branch (Option 3), or discarding (Option 4) in the current session, agents **must** execute **Option 2** automatically without waiting for manual prompting—and **must** automatically add the single PR to the Merge Queue or automatically add Stacked PRs to the stack, submit them, and queue the stack for merge.

If asking interactively, present these 4 options:

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Don't add explanation** - keep options concise.

### Step 4: Execute Choice

#### Option 1: Merge Locally

```bash
# Switch to base branch
git checkout <base-branch>

# Pull latest
git pull

# Merge feature branch
git merge <feature-branch>

# Verify tests on merged result
<test command>

# If tests pass
git branch -d <feature-branch>
```

Then: Cleanup worktree (Step 5)

#### Option 2: Push and Create PR (Automatic Merge Queue & Stack Enrollment)

**Case A — Single Pull Request (pull/rebase `origin/main`, open PR, and automatically add the single PR to the Merge Queue):**

```bash
# Pull/rebase all latest changes from the default branch so the PR is never outdated or conflicted
git fetch origin main && git rebase origin/main

# Push branch
git push -u origin <feature-branch>

# Create PR using .github/pull_request_template.md with session-verified diff stat and test exit codes
mise exec gh -- gh pr create --base main --head <feature-branch> --title "<type>(<scope>): <description>" --body-file <populated-pr-body-file>

# If origin/main advanced while opening the PR, immediately rebase the PR branch on GitHub
mise exec gh -- gh pr update-branch <pr-number> --rebase

# Immediately and automatically add the single PR to the Merge Queue (squash merge once CI Gate passes)
mise exec gh -- gh pr merge <pr-number> --auto --squash
```

**Case B — Stacked Pull Requests (automatically add Stacked PRs to the stack, sync with `origin/main`, and queue via `gh-stack`):**

```bash
# Automatically add Stacked PRs to the stack as each layer is created (explicit <type>/<scope>/<short-desc> names)
mise exec gh -- gh stack create <first-branch>
# ... commit layer 1, then add subsequent layers to the stack automatically:
mise exec gh -- gh stack add <next-branch>
mise exec gh -- gh stack view

# Pull/rebase all latest changes from the default branch into the stack so no layer is outdated or conflicted
git fetch origin main && mise exec gh -- gh stack sync

# Automatically push all stack branches and open/link stacked PRs on GitHub
mise exec gh -- gh stack submit --auto

# Populate each layer PR's Conventional Commit title and .github/pull_request_template.md body
# (using git diff --no-textconv --stat <parent-branch>...<layer-branch> for each layer)
mise exec gh -- gh pr edit <layer-pr-number> --title "<type>(<scope>): <layer-description>" --body-file <layer-pr-body-file>

# Immediately and automatically queue the stack (or bottom-up subset) into the GitHub Merge Queue
# (Note: gh pr merge --auto is not supported on stacked PRs; always use gh stack merge)
mise exec gh -- gh stack merge [<pr-or-stack>] --yes
```

Then: Keep worktree until queued PR(s) merge (Step 5)

#### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

**Don't cleanup worktree.**

#### Option 4: Discard

**Confirm first:**

```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

If confirmed:

```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

Then: Cleanup worktree (Step 5)

### Step 5: Cleanup Worktree

**For Options 1, 2, 4:**

Check if in worktree:

```bash
git worktree list | grep $(git branch --show-current)
```

If yes:

```bash
git worktree remove <worktree-path>
```

**For Option 3:** Keep worktree.

## Quick Reference

| Option           | Merge | Push | Keep Worktree | Cleanup Branch |
| ---------------- | ----- | ---- | ------------- | -------------- |
| 1. Merge locally | ✓     | -    | -             | ✓              |
| 2. Create PR     | -     | ✓    | ✓             | -              |
| 3. Keep as-is    | -     | -    | ✓             | -              |
| 4. Discard       | -     | -    | -             | ✓ (force)      |

## Common Mistakes

**Skipping test verification**

- **Problem:** Merge broken code, create failing PR
- **Fix:** Always verify tests before offering options

**Open-ended questions**

- **Problem:** "What should I do next?" → ambiguous
- **Fix:** Present exactly 4 structured options

**Automatic worktree cleanup**

- **Problem:** Remove worktree when might need it (Option 2, 3)
- **Fix:** Only cleanup for Options 1 and 4

**No confirmation for discard**

- **Problem:** Accidentally delete work
- **Fix:** Require typed "discard" confirmation

## Red Flags

**Never:**

- Proceed with failing tests
- Merge without verifying tests on result
- Delete work without confirmation
- Force-push without explicit request

**Always:**

- Verify tests before offering options
- Present exactly 4 options
- Get typed confirmation for Option 4
- Clean up worktree for Options 1 & 4 only

## Integration

**Called by:**

- **single-flow-task-execution** (final step) - After all tasks complete
- **executing-plans** (Step 5) - After all batches complete

**Pairs with:**

- **using-git-worktrees** - Cleans up worktree created by that skill
