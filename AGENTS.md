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
  - `secrets/credentials.ci.sops.yaml`: Encrypted via Age for continuous integration pipelines, automated linting, and Molecule testing.
  - `secrets/credentials.sops.yaml`: Encrypted via GPG for production operations and administrative deployments.
  - Creating separate, domain-specific, or ad-hoc secret files (e.g., `secrets.*.sops.yaml`) is strictly forbidden. All secrets must be consolidated into these two canonical files.
- **No Textconv Diff on Production Secrets:** Always execute git diff operations with `--no-textconv` (e.g., `git diff --no-textconv`) when inspecting diffs or changes to ensure decrypted secrets are never accidentally materialized or printed into tool execution output or chat history.
- **Forbid Secret Getter Invocations:** AI agents are strictly forbidden from executing commands such as `mise run secret:*:get` or any scripts/commands whose purpose is to dump or display decrypted secret keys and credentials in logs or chat.

---

## 🏗️ 2. OpenTofu (Terraform) Standards

Keep declarative infrastructure well-structured and secure. The hard rules below are binding. The full standard (file layout, versions and locks, state and encryption, validation, lifecycle, testing, drift) is in [`docs/runbooks/opentofu-standards.md`](docs/runbooks/opentofu-standards.md) (see §6).

- **Separation of Concerns:** Split every module into single-purpose files (`versions.tf`, `providers.tf`, `backend.tf`, `encryption.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `main.tf`, plus domain files). The exact layout is in the runbook (STD-OT-03).
- **Ambiguous Sensitivity:** All variables and outputs that deal with state, domain names, network IDs, or credentials must default to `sensitive = true`.
- **TFLint & Formats:** Always run `tofu fmt` and `tflint` (after `tflint --init`, with the repository `.tflint.hcl` passed via `--config`) locally before completing a task. Never commit unformatted `.tf` code.
- **Always Free Tier Hard Gate:** All cloud infrastructure must strictly use the Always Free Tier. If resources will be used/added that are not in the always free tier, this is a hard gate that must be explicitly approved first by the user. Vendors change free-tier limits, so re-verify the limit against vendor documentation whenever a sizing gate is touched.
  - _Approved exceptions:_ Azure budget ceiling of $165/month (owner decision D4, 2026-10-13).
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
- **Trunk-Based Development:** Create short-lived feature branches and merge them to `main` via squash-merged PRs that pass `CI Gate`. Only the repository owner may merge small changes locally, and history must stay linear (rebase and fast-forward, or squash; no merge commits). Agents open a PR unless the owner explicitly asks for a local merge in that session.
- **Branch Naming:** All task branches must be named following the pattern: `<type>/<scope>/<short-desc>` (e.g., `feat/gcp/state-bucket`).
- **Plan File Location:** All plan files should be stored at: `docs/plans` (e.g., `docs/plans/2026-06-01-short-plan-name.md`).
- **Git Worktrees Mandatory:** When running tasks that add, update, or delete files, you **must** use isolated git worktrees rather than modifying the main workspace directly. Consult the `.agent/skills/using-git-worktrees/SKILL.md` skill for the proper directory selection and setup process.
- **Automated Pull Request Creation:** If a task or feature branch is not merged locally into `main` and a separate branch is pushed to `origin`, a Pull Request **must** be created automatically for that branch. The Pull Request must have a descriptive title adhering to the Conventional Commits specification (e.g., `feat(cloudflare): configure spend alerts and pr automation`) and a detailed description documenting all changes, architectural rationale, and verification test results included in the branch.

---

## 📋 5. Self-Review and Task Verification

- **Mandatory Test Coverage for Added/Changed Scope:** Any added, updated, or expanded functionality, configuration, script, or infrastructure scope **must** include corresponding automated tests (e.g., Bats unit tests in `tests/scripts/`, OpenTofu native tests in `infrastructure/<module>/tests/*.tftest.hcl`, or Molecule scenarios in `configuration/roles/*/molecule/`). Never declare a feature or scope complete without accompanying automated tests verifying its correctness.

Before claiming a task is complete, verify your work:

1.  **Run local lint and tests** on changed files. Use the correct tool for the domain. The complete per-domain command lists are in each runbook's "Verification commands" section (§6):
    - **OpenTofu changes:** `mise exec -- tofu fmt -check -recursive infrastructure` · `mise exec -- tflint --init --config "$PWD/.tflint.hcl"` then `mise exec -- tflint --recursive --config "$PWD/.tflint.hcl"` (from the repo root) · `mise exec -- tofu init -backend=false && mise exec -- tofu validate` (per module) · `mise run test:infra` and `mise run test:tofu:children` (native `tofu test` suites)
    - **Ansible changes:** `mise exec -- ansible-lint configuration/` · Molecule test suites:
      - `(cd configuration/roles/base_ubuntu_server && mise exec -- molecule test)`
      - `(cd configuration/roles/restic_backup && mise exec -- molecule test)`
      - `(cd configuration && mise exec -- molecule test -s oci)`
      - `(cd configuration && mise exec -- molecule test -s homelab)`
    - **Script changes:** `mise exec -- shellcheck scripts/*.sh tests/scripts/helpers/*` · `mise exec -- bats tests/scripts/`
    - **Workflow / Renovate changes:** `mise exec -- actionlint` · the CI-related bats suites listed in `docs/runbooks/ci-workflows-standards.md` §15
    - **Python changes:** `uv run ruff check` · `uv run ruff format --check`
    - **Pre-commit gate (all changes):** `mise exec lefthook -- lefthook run pre-commit`
    > **Note:** Current Molecule tests target Ubuntu Server 26.04 via the Docker driver across the four scenarios above (`base_ubuntu_server`, `restic_backup`, `oci`, and `homelab`).
2.  **Verify exit status** — all commands above must exit 0 before proceeding.
3.  **Perform a self-review diff** of your modifications to ensure no stray code, unused variables, or comments remain.
4.  **Update the task tracker** located at `docs/plans/task.md` during execution (this file is ignored by Git to avoid worktree merge conflicts). Upon completing all tasks for a branch or plan, move `docs/plans/task.md` to `docs/plans/archive/task-<YYYY-MM-DD>-<topic>.md` and commit the archived tracker.

---

## 📚 6. Engineering Standards (Runbooks)

Every addition or change must follow the domain standard below, in addition to the hard rules in this file:

| Domain                  | Standard                                                                                          | Covers                                                                                                                                                                                                                                       |
| :---------------------- | :------------------------------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OpenTofu                | [`docs/runbooks/opentofu-standards.md`](docs/runbooks/opentofu-standards.md) (`STD-OT-*`)         | module layout, versions & lock files, state backend & encryption, secrets & sensitivity, validation, tagging & Always-Free limits, lifecycle, networking & IAM, `tofu test`, linting & scanning, drift, upgrades                             |
| Ansible                 | [`docs/runbooks/ansible-standards.md`](docs/runbooks/ansible-standards.md) (`STD-AN-*`)           | layout & naming, toolchain & Galaxy pins, lint, `community.sops` secrets & systemd credentials, idempotency & error handling, privilege, templates & units, role interfaces, inventory, firewall & containers, backups, Molecule, check mode |
| CI workflows & Renovate | [`docs/runbooks/ci-workflows-standards.md`](docs/runbooks/ci-workflows-standards.md) (`STD-CI-*`) | triggers & `CI Gate`, permissions, pinning & supply chain, secrets & environments, public-log hygiene, injection safety, caching, timeouts, quality gates, scheduled workflows, scanning, Renovate policy, governance as code                |

- **Precedence:** the runbooks add detail and **never relax or override** a rule in this file. If they conflict, this file wins; fix the runbook in the same PR.
- **Rule IDs:** cite the `STD-*` rule IDs in reviews, commit bodies and PR descriptions. A deviation from a **MUST** rule needs explicit owner approval, recorded as described in the runbook.
- **Encrypted runbooks:** the runbooks live under `docs/**` and are **git-crypt encrypted**. If `git-crypt status docs/runbooks/` reports them as `encrypted`, or a file starts with the `\0GITCRYPT` header, you do not have the key. In that case:
  1. Do not try to decrypt, edit, reformat, regenerate, rename or delete them.
  2. Follow the hard rules in this file, which are complete on their own, and mirror the conventions already used in neighbouring code.
  3. State in your PR description: "Runbooks unavailable (encrypted); followed AGENTS.md hard rules and existing patterns."
- **Current gaps:** known deviations from the standards are tracked in `docs/plans/2026-10-13-infrastructure-review-2-improvement-plan.md`. New code must follow the standards regardless.
