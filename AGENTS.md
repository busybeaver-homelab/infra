# 🤖 Operational Guardrails for AI Agents (`AGENTS.md`)

This repository is designed for collaborative human-agent engineering. To ensure security, maintainability, and architectural integrity, all AI agents (including Antigravity, GitHub Copilot, and other LLM assistants) **MUST** strictly follow the operational rules defined in this document without exception.

---

## 🔒 1. Secrets Management & Privacy

> **Precedence Contract:** This document is the supreme, authoritative operational, security, and architectural policy for this repository. All human operators, AI assistants, and runtime profiles (including `.agent/AGENTS.md`) must strictly comply with the requirements herein without exception. In any event of conflicting guidance, this document strictly supersedes all other instructions.

Security is the absolute highest priority in this repository.

- **SOPS-Only Rule:** All secrets, configuration files containing credentials, and API variables **must** be encrypted via SOPS. Ansible Vault is strictly forbidden.
- **No Plaintext Leaks:** Never commit raw passwords, private keys, API tokens, or other sensitive credentials in plaintext.
- **Re-Encrypt Immediately:** If you decrypt a secret for local editing or verification, ensure it is re-encrypted before completing your task.
- **Privacy in Conversations:** Never output decrypted secrets, private keys, or API tokens into the chat/transcript.
- **Masking Network Details:** All internal IPs, subnets, internal hostnames, and server domains are classified as sensitive. Treat them as encrypted secrets; do not hardcode them in open playbooks, variables, or OpenTofu manifests.
- **Canonical Two-File Secrets Architecture:** All secrets, tokens, and credentials across the entire repository **must** reside exclusively in exactly two canonical files:
  - `secrets/credentials.ci.sops.yaml`: Encrypted via Age for continuous integration pipelines, automated linting, and Molecule testing. It should only contain decoy or dummy values, never production values (i.e. never the same values as the production file; enforced automatically via `scripts/check-sops-secret-leaks.sh --check-disjointness`).
  - `secrets/credentials.sops.yaml`: Encrypted via GPG for production operations and administrative deployments.
  - Creating separate, domain-specific, or ad-hoc secret files (e.g., `secrets.*.sops.yaml`) is strictly forbidden. All secrets must be consolidated into these two canonical files.
- **Synthetic Test Fixtures Only:** Automated tests (`.bats`, `.tftest.hcl`, Molecule scenarios, and mock fixtures) are **never** exempt from secret or network masking scanners (`scripts/check-sops-secret-leaks.sh`, `scripts/check-network-masking.sh`, `scripts/detect-private-keys.sh`). Tests **must never** contain values copied from `secrets/credentials.sops.yaml` or `secrets/credentials.ci.sops.yaml`. Always use RFC 2606 domains (`example.com`, `example.test`), RFC 5737 TEST-NET IPs (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`), RFC 3849 IPv6 (`2001:db8::/32`), dynamically generated runtime keys (`age-keygen`, `openssl rand`), or, in negative scanner tests only, split-string construction of **synthetic** values. Splitting, encoding or truncating a real value from either SOPS file is never permitted; it evades the leak scanner rather than satisfying it.
- **No Textconv Diff on Production Secrets:** Always execute git diff operations with `--no-textconv` (e.g., `git diff --no-textconv`) when inspecting diffs or changes to ensure decrypted secrets are never accidentally materialized or printed into tool execution output or chat history.
- **Forbid Secret Getter Invocations:** AI agents are strictly forbidden from executing commands such as `mise run secret:*:get` or any scripts/commands whose purpose is to dump or display decrypted secret keys and credentials in logs or chat.
- **Prohibited commands (`R2-GOV-05`):** Agents never run whole-file `sops -d`/`sops decrypt`, `tofu state pull`, `tofu show` on state or plan files, `tofu output` (any form), or `git-crypt export-key`. This extends the existing `secret:*:get` ban. Exception: repository scripts that consume these outputs internally without printing them, such as `generate-inventory.sh` and `get-tofu-restic-vars.sh`. Agents may run them only under the **Per-action human confirmation** rule in §4.
- **No silent secret fallbacks (`R2-GOV-05`):** If a required secret is missing, the code fails closed. It never falls back to CI decoys, placeholders or defaults.
- **Derived stores (`R2-GOV-05`):** GitHub environments, cloud IAM keys and host systemd credential stores are filled only by repository code, from the two canonical SOPS files or OpenTofu outputs. Never by hand.

---

## 🏗️ 2. OpenTofu (Terraform) Standards

Keep declarative infrastructure well-structured and secure. The hard rules below are binding. The full standard (file layout, versions and locks, state and encryption, validation, lifecycle, testing, drift) is in [`docs/runbooks/opentofu-standards.md`](docs/runbooks/opentofu-standards.md) (see §6).

- **Separation of Concerns:** Split every module into single-purpose files (`versions.tf`, `providers.tf`, `backend.tf`, `encryption.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `main.tf`, plus domain files). The exact layout is in the runbook (STD-OT-03).
- **Ambiguous Sensitivity:** All variables and outputs that deal with state, domain names, network IDs, or credentials must default to `sensitive = true`.
- **TFLint & Formats:** Always run `tofu fmt` and `tflint` (after `tflint --init`, with the repository `.tflint.hcl` passed via `--config`) locally before completing a task. Never commit unformatted `.tf` code.
- **Always Free Tier Hard Gate:** All cloud infrastructure must strictly use the Always Free Tier. If resources will be used/added that are not in the always free tier, this is a hard gate that must be explicitly approved first by the user. Vendors change free-tier limits, so re-verify the limit against vendor documentation whenever a sizing gate is touched.
  - _Approved exceptions:_
    - Azure budget ceiling of $165/month (owner decision D4, 2026-10-13).
    - `STD-OT-49` (`infrastructure/gcp`): GCP Always Free `e2-micro` (`gcp-default-vm`) attaches 1 free `STANDARD`-tier ephemeral external IPv4 for outbound internet and inbound `UDP 41641` Tailscale WireGuard direct peering because GCP Cloud NAT is a paid service (owner decision A2, 2026-10-14).
- **Mandatory Resource Tagging:** All cloud resources across all providers must be tagged/labeled with `project = "homelab"` (e.g., via `freeform_tags` in OCI, `labels` in GCP, or `tags` in Azure). When merging resource-specific tags, the mandatory map must be merged **last** (e.g., `merge(local.effective_tags, { role = "backup" }, { project = "homelab" })`) so that `project = "homelab"` can never be omitted or overridden.

---

## 🏎️ 3. Ansible Configuration Standards

Keep Ansible configuration idempotent and maintainable. The hard rules below are binding. The full standard (layout, dependencies, secrets delivery, error handling, inventory, firewall, Molecule testing) is in [`docs/runbooks/ansible-standards.md`](docs/runbooks/ansible-standards.md) (see §6).

- **Production Profile:** `ansible-lint` is configured with the strict `production` profile. You must use **Fully Qualified Collection Names (FQCN)** (e.g., use `ansible.builtin.copy` instead of `copy`).
- **Decoupled Secrets:** Utilize the `community.sops` collection to read values on the fly instead of storing variables in plaintext or vault-encrypted files.
- **Idempotency:** All tasks and plays must be strictly idempotent. Ensure handlers are used where appropriate and files have proper owners and permissions set.

---

## 🛑 4. Pre-Commit Hooks & Git Discipline

Automated gates must be respected. Changes to GitHub workflows, the composite setup action, Renovate or repository settings additionally follow [`docs/runbooks/ci-workflows-standards.md`](docs/runbooks/ci-workflows-standards.md) (see §6).

- **Strictly No Bypassing Hooks:** It is **strictly forbidden** to bypass Git hooks. Under no circumstance should you run Git commands with `--no-verify`. If a hook fails, you must diagnose, fix, and rerun the hook until it passes.
- **Verification Command:** Before submitting work or claiming a task is done, run local linting and testing commands (e.g., `mise exec lefthook -- lefthook run pre-commit`) to guarantee your changes comply with repo guidelines.
- **Conventional Commits:** You must format every commit message according to the Conventional Commits specification.
  - _Examples:_ `feat(gcp): add compute engine instance`, `fix(unifi): update dhcp leases sops secret`.
- **Trunk-Based Development & Merge Queue:** Create short-lived feature branches from the latest `origin/main` (or a reviewable PR stack via `gh stack`; see below) and merge them to `main` via squash-merged PRs queued through the **GitHub Merge Queue** (`merge_group` trigger) that pass `CI Gate` (`gh pr merge <pr-number> --auto --squash` for single PRs, or `gh stack merge [<pr-or-stack>] --yes` for stacked PRs). Only the repository owner may merge small changes locally, and history must stay linear (rebase and fast-forward, or squash; no merge commits). Unless the owner explicitly asks for a local merge in that session, agents **must** pull/rebase all latest changes from `origin/main`, automatically open the PR (or PR stack), **automatically add the single PR to the Merge Queue**, and **automatically add Stacked PRs to the stack** and queue the stack for merge without waiting for manual prompting, except for PRs covered by the Owner-Review Exception below. Owner local merge: `git switch main && git merge --ff-only <branch> && ALLOW_MAIN_PUSH=1 git push origin main`. The `pre-push` guard (`scripts/guard-main-push.sh`, active after `lefthook install` once per clone) blocks every other push to `main` and rejects creating a remote feature branch that does not contain `origin/main`.
- **Stacked Pull Requests (`gh-stack`):** Default to a single PR automatically added to the Merge Queue (`mise exec gh -- gh pr merge <pr-number> --auto --squash`) for small or single-concern tasks. Use **Stacked Pull Requests** via the `gh-stack` skill (`.agents/skills/gh-stack/SKILL.md` / `gh stack` CLI extension) when a task has multiple dependent logical layers (e.g., foundation/helper -> OpenTofu module -> Ansible role -> CI/docs) or a large diff (> ~400 lines) that benefits from atomic reviewable layers:
  - Automatically register every layer branch in the stack as you build it: run `mise exec gh -- gh stack create <first-branch>` for layer 1 and `mise exec gh -- gh stack add <next-branch>` for each subsequent layer, always passing an explicit `<type>/<scope>/<short-desc>` branch name (never rely on `gh stack add -Am` auto-generated `MM-DD-slug` branch names, which fail the `pr-metadata` CI gate).
  - Before submitting the stack, always fetch and sync with the latest default branch (`git fetch origin main && mise exec gh -- gh stack sync`) so no layer in the stack is outdated or has merge conflicts with `main`.
  - Automatically push all layers and open/link PRs in the stack on GitHub by running `mise exec gh -- gh stack submit --auto` (`gh stack sync` after rebasing or editing an earlier layer).
  - Format every layer PR's title (Conventional Commits) and body (`.github/pull_request_template.md` with per-layer `git diff --no-textconv --stat <parent-branch>...<layer-branch>`) via `mise exec gh -- gh pr edit <pr-number>`.
  - Automatically queue the stack for merge via `mise exec gh -- gh stack merge [<pr-or-stack>] --yes` (which submits eligible bottom-up layers into the GitHub Merge Queue; `gh pr merge --auto` is not supported on stacked PRs).
- **Branch Naming:** All task branches (including every layer branch in a PR stack) must be named following the pattern: `<type>/<scope>/<short-desc>` (e.g., `feat/gcp/state-bucket`).
- **Plan File Location:** All plan files should be stored at: `docs/plans` (e.g., `docs/plans/2026-06-01-short-plan-name.md`).
- **Git Worktrees Mandatory:** When running tasks that add, update, or delete files, you **must** use isolated git worktrees rather than modifying the main workspace directly. Consult the `.agent/skills/using-git-worktrees/SKILL.md` skill for the proper directory selection and setup process. Always run `git fetch origin main` first and create the worktree branch directly from `origin/main` (`--no-track -b <branch> origin/main`; `--no-track` stops `origin/main` from becoming the branch's upstream) so work never starts from a stale local commit. In this repo, `git-crypt` and worktrees need extra setup: when the main repository is unlocked (`.git/git-crypt` exists), create the worktree with `--no-checkout`, symlink `../../git-crypt` into `.git/worktrees/<n>/git-crypt`, and then run `git -C <worktree> checkout`—otherwise the encrypted runbooks under `docs/` (and other `git-crypt`-protected paths) arrive as `\0GITCRYPT` blobs.
- **Automated Pull Request Creation, Stacking, and Merge Queue Enrollment:** If a task or feature branch (or PR stack) is not merged locally into `main` and is pushed to `origin`, the agent **must** pull in all latest changes from `origin/main`, automatically create the Pull Request(s), link any stacked PRs into their stack, and enroll the PR(s) into the Merge Queue in the same session without waiting for manual prompting (subject to the Owner-Review Exception below):
  - **Default-Branch Synchronization Before Opening PRs:** Each time a PR (or PR stack) is opened, all changes from the default branch (`origin/main`) **must** be pulled in first so the branch is never outdated or conflicted: run `git fetch origin main && git rebase origin/main` before pushing a single PR (or `git fetch origin main && mise exec gh -- gh stack sync` before submitting a stack), resolve any merge conflicts locally, and re-run affected verification checks. Once the PR is open, do not rebase it only because `origin/main` moved: the Merge Queue tests every entry against the latest `main`. Rebase only when GitHub reports a merge conflict, and do it locally (`git fetch origin main && git rebase origin/main`, then `git push --force-with-lease`; `mise exec gh -- gh stack sync` for stacks) so the local branch and recorded task-tracker SHAs stay in step with the PR.
  - **Single PR — Automatic Merge Queue Enrollment:** Immediately after rebasing onto `origin/main`, pushing the branch, and creating the PR with `mise exec gh -- gh pr create` (using `.github/pull_request_template.md`), the agent **must** automatically add the single PR to the Merge Queue via `mise exec gh -- gh pr merge <pr-number> --auto --squash`.
  - **Stacked PRs — Automatic Stack Registration, Submission, and Queueing:** When a task uses a PR stack, the agent **must** automatically add each layer branch to the stack (`mise exec gh -- gh stack create <first-branch>` and `mise exec gh -- gh stack add <next-branch>`), sync the stack with `origin/main` (`git fetch origin main && mise exec gh -- gh stack sync`), automatically push and link all PRs into the GitHub stack via `mise exec gh -- gh stack submit --auto`, populate each layer PR's title and `.github/pull_request_template.md` body via `mise exec gh -- gh pr edit <pr-number>`, and automatically queue the stack in the Merge Queue via `mise exec gh -- gh stack merge [<pr-or-stack>] --yes`.
  - **Owner-Review Exception (CODEOWNERS paths):** If a PR, or any layer of a PR stack, changes a path owned in `.github/CODEOWNERS` (e.g., `AGENTS.md`, `lefthook.yml`, `scripts/guard-*`, `secrets/`, `infrastructure/github/`), the agent **must not** enroll it in the Merge Queue (`gh pr merge --auto`) or include it in `gh stack merge`. Open the PR, state in the PR body and in the session that it awaits owner review, and leave queueing to the owner. Stack layers below the first owned layer may still be queued (`mise exec gh -- gh stack merge <last-unowned-layer-pr> --yes`).
  - **PR Metadata & Privacy Requirements:** Every PR must have a descriptive title adhering to the Conventional Commits specification (e.g., `feat(cloudflare): configure spend alerts and pr automation`) and a comprehensive description documenting all changes, architectural rationale, and verification test results included in the branch. Every file path, test name, and count in a PR body **must** be copied from command output executed in the same session (`git diff --stat main...HEAD` or per-layer `git diff --no-textconv --stat <parent-branch>...<layer-branch>`, `bats`, `tofu test`, etc.). Pull Request titles and descriptions **must never contain sensitive information or secrets** (including internal IPs, subnets, internal hostnames, server domains, or credentials—those must reside exclusively in the canonical SOPS files or `git-crypt`-encrypted files).
- **Agent Directory Ownership (`.agent/` vs `.agents/`):** `.agent/` is owned by the Antigravity Superpowers profile (`npx --yes antigravity-superpowers@0.1.0 init`; see `.agent/INSTALL.md`), whereas `.agents/skills/` is owned by the `skills` CLI (`npx --yes skills@1.7.2`) and integrity-locked by `skills-lock.json` (verified by `scripts/verify-skills-lock.sh`).
- **Per-action human confirmation (`R2-GOV-05`):** Agents state the exact effect and get an explicit yes, separately for every invocation, before running:
  - `tofu apply`, `destroy`, `import` and `state mv|rm`;
  - `ansible-playbook` against real inventory;
  - `mise run github:sync*` and `sync:cloudflare:budget`;
  - `scripts/bootstrap-state-backend.sh`.
    A yes for one action never covers another.

---

## Model maintenance

Before substantive repository work, check the offline model review record and follow [agent model maintenance](docs/runbooks/agent-model-maintenance.md) when review is due or a vendor change is known. Model mapping and approved resolution changes require explicit owner approval through the owner-review PR path before merge or activation.

---

## 📋 5. Self-Review and Task Verification

- **Mandatory Test Coverage for Added/Changed Scope:** Any added, updated, or expanded functionality, configuration, script, or infrastructure scope **must** include corresponding automated tests (e.g., Bats unit tests in `tests/scripts/`, OpenTofu native tests in `infrastructure/<module>/tests/*.tftest.hcl`, or Molecule scenarios in `configuration/roles/*/molecule/`). Never declare a feature or scope complete without accompanying automated tests verifying its correctness.

Before claiming a task is complete, verify your work:

1.  **Run local lint and tests** on changed files. Use the correct tool for the domain. The complete per-domain command lists are in each runbook's "Verification commands" section (§6):
    - **OpenTofu changes:** `mise exec -- tofu fmt -check -recursive infrastructure` · `mise exec -- tflint --init --config "$PWD/.tflint.hcl"` then `mise exec -- tflint --recursive --config "$PWD/.tflint.hcl"` (from the repo root) · `mise exec -- tofu init -backend=false && mise exec -- tofu validate` (per module) · `mise run test:infra` and `mise run test:tofu:children` (native `tofu test` suites)
    - **Ansible changes:** `mise exec -- ansible-lint configuration/` · Molecule test suites:
      - `(cd configuration/roles/base_ubuntu_server && mise exec -- molecule test)`
      - `(cd configuration/roles/restic_backup && mise exec -- molecule test)`
      - `(cd configuration/roles/docker_compose_service && mise exec -- molecule test)`
      - `(cd configuration && mise exec -- molecule test -s oci)`
      - `(cd configuration && mise exec -- molecule test -s gcp)`
      - `(cd configuration && mise exec -- molecule test -s homelab)`
    - **Script / Secrets changes:** `mise exec -- shellcheck scripts/*.sh tests/scripts/helpers/*` · `mise exec -- bats tests/scripts/` · `mise exec -- bash scripts/check-sops-secret-leaks.sh --check-disjointness --all-files`
    - **Workflow / Renovate changes:** `mise exec -- actionlint` · the CI-related bats suites listed in `docs/runbooks/ci-workflows-standards.md` §15
    - **Python changes:** `uv run --locked ruff check` · `uv run --locked ruff format --check`
    - **Pre-commit gate (all changes):** `mise exec lefthook -- lefthook run pre-commit`
    > **Note:** Current Molecule tests target Ubuntu Server 26.04 via the Docker driver across the six scenarios above (`base_ubuntu_server`, `restic_backup`, `docker_compose_service`, `oci`, `gcp`, and `homelab`).
2.  **Verify exit status** — all commands above must exit 0 before proceeding.
3.  **Perform a self-review diff** of your modifications to ensure no stray code, unused variables, or comments remain.
4.  **Update the task tracker** located at `docs/plans/task.md` during execution (this file is ignored by Git to avoid worktree merge conflicts). Marking any item `Done` in a status or task tracker requires recording the commit SHA and verification command that proved it. The SHA must stay reachable from the PR head: if you rebase after recording it, update the tracker before pushing. Upon completing all tasks for a branch or plan, move `docs/plans/task.md` to `docs/plans/archive/task-<YYYY-MM-DD>-<topic>.md` and commit the archived tracker.

---

## 📚 6. Engineering Standards (Runbooks)

Every addition or change must follow the domain standard below, in addition to the hard rules in this file:

| Domain                  | Standard                                                                                          | Covers                                                                                                                                                                                                                                           |
| :---------------------- | :------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OpenTofu                | [`docs/runbooks/opentofu-standards.md`](docs/runbooks/opentofu-standards.md) (`STD-OT-*`)         | module layout, versions & lock files, state backend & encryption, secrets & sensitivity, validation, tagging & Always-Free limits, lifecycle, networking & IAM, `tofu test`, linting & scanning, drift, upgrades                                 |
| Ansible                 | [`docs/runbooks/ansible-standards.md`](docs/runbooks/ansible-standards.md) (`STD-AN-*`)           | layout & naming, toolchain & Galaxy pins, lint, `community.sops` secrets & systemd credentials, idempotency & error handling, privilege, templates & units, role interfaces, inventory, firewall & containers, backups, Molecule, check mode     |
| CI workflows & Renovate | [`docs/runbooks/ci-workflows-standards.md`](docs/runbooks/ci-workflows-standards.md) (`STD-CI-*`) | triggers & `CI Gate`, permissions, pinning & supply chain, secrets & environments, public-log hygiene, injection safety, caching, timeouts, quality gates, scheduled workflows, scanning, Renovate policy, governance, merge queue & stacked PRs |

- **Precedence:** the runbooks add detail and **never relax or override** a rule in this file. If they conflict, this file wins; fix the runbook in the same PR.
- **Rule IDs:** cite the `STD-*` rule IDs in reviews, commit bodies and PR descriptions. A deviation from a **MUST** rule needs explicit owner approval, recorded as described in the runbook.
- **Encrypted runbooks:** the runbooks live under `docs/**` and are **git-crypt encrypted**. If `git-crypt status docs/runbooks/` reports them as `encrypted`, or a file starts with the `\0GITCRYPT` header, you do not have the key. In that case:
  1. Do not try to decrypt, edit, reformat, regenerate, rename or delete them.
  2. Follow the hard rules in this file, which are complete on their own, and mirror the conventions already used in neighbouring code.
  3. State in your PR description: "Runbooks unavailable (encrypted); followed AGENTS.md hard rules and existing patterns."
- **Current gaps:** known deviations from the standards are tracked in `docs/plans/2026-10-13-infrastructure-review-2-improvement-plan.md`. New code must follow the standards regardless.

---

## 7. Automatic Agent Routing

Apply this policy independently in Codex, Claude, and Antigravity. The approved native and resolved model mappings and reasoning efforts are maintained in `.agent-models.json`; use those mappings rather than inventing replacements. No client installation, login, or live model call is required to work in another client or to validate configuration offline.

| Responsibility                                                               | Codex        | Claude | Antigravity |
| ---------------------------------------------------------------------------- | ------------ | ------ | ----------- |
| Coordinator: architecture, security, critical decisions and final assessment | Sol/high     | Opus   | Pro         |
| Implementer: bounded, already-designed changes                               | Terra/medium | Sonnet | Flash       |
| Simple: unambiguous mechanical work                                          | Luna/medium  | Haiku  | Flash       |
| Reviewer: independent strong review                                          | Sol/high     | Opus   | Pro         |

Classify content and risk before editing. Before edits, record the selected role, expected model, allowed scope, and acceptance checks in the ignored worktree-local docs/plans/task.md. Update this evidence as routing and corrections advance. Automatically delegate safely separable, already-designed mechanical substeps to the appropriate role when delegation is available. Ambiguous design, IAM, state, credentials, encryption, and enforcement-boundary decisions remain with the strong coordinator. If a task cannot be divided safely, the coordinator performs it entirely; do not force delegation of critical decisions or silently use a cheaper model for them.

The coordinator supplies each worker a bounded handoff with plan scope, allowed files, acceptance checks, and guardrails. Use the simple role for unambiguous mechanical work and the implementer for bounded changes. Explicitly request named custom roles when supported; if the harness exposes only model and effort spawn parameters, pass the approved manifest values explicitly. Keep one active writer and no nested workers. Workers must not deploy, push, merge, or declare final completion; the coordinator controls Git and deployment, subject to all existing restrictions and per-action human confirmation above.

After one unsuccessful simple correction, promote the work to an implementer. After two unsuccessful implementer correction rounds, escalate to the strong coordinator. Antigravity Flash roles share one two-round budget. Escalate immediately on ambiguity, security concerns, scope expansion, or model mismatch. If a worker is unavailable, promote to the strong coordinator with notice. If the strong model is unavailable, stop that client's edits and assessment; this does not block unrelated inactive clients or offline delivery. If delegation is unsupported, retain the work with the strong coordinator and record that limitation. Observe model identity from available metadata; do not claim identity based only on self-report or configuration.

After implementation is idle, request a separate strong reviewer. Before final completion, the coordinator assesses the review, the diff, and exact verification commands and exit statuses. Review is instructional where the client does not provide a separate read-only sandbox; existing permission controls remain in force. Routing grants no deployment approval and does not relax any existing security, masking, worktree, hook, or owner-review rule.
