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

Keep declarative infrastructure well-structured and secure:

- **Separation of Concerns:** Always split OpenTofu configurations into logical, single-purpose files:
  - `main.tf` (resources and data sources)
  - `variables.tf` (inputs)
  - `outputs.tf` (outputs)
  - `providers.tf` (provider configuration and versions)
  - `versions.tf` (required OpenTofu and provider versions)
- **Ambiguous Sensitivity:** All variables and outputs that deal with state, domain names, network IDs, or credentials must default to `sensitive = true`.
- **TFLint & Formats:** Always run `tofu fmt` and `tflint` locally before completing a task. Never commit unformatted `.tf` code.
- **Always Free Tier Hard Gate:** All cloud infrastructure must strictly use the Always Free Tier. If resources will be used/added that are not in the always free tier, this is a hard gate that must be explicitly approved first by the user.
- **Mandatory Resource Tagging:** All cloud resources across all providers must be tagged/labeled with `project = "homelab"` (e.g., via `freeform_tags` in OCI, `labels` in GCP, or `tags` in Azure). For resources requiring additional resource-specific tags, default tags must be merged using `merge(var.default_freeform_tags, { ... })` (or provider equivalent) so that `project = "homelab"` is never omitted.

---

## 🏎️ 3. Ansible Configuration Standards

Keep Ansible configuration idempotent and maintainable:

- **Production Profile:** `ansible-lint` is configured with the strict `production` profile. You must use **Fully Qualified Collection Names (FQCN)** (e.g., use `ansible.builtin.copy` instead of `copy`).
- **Decoupled Secrets:** Utilize the `community.sops` collection to read values on the fly instead of storing variables in plaintext or vault-encrypted files.
- **Idempotency:** All tasks and plays must be strictly idempotent. Ensure handlers are used where appropriate and files have proper owners and permissions set.

---

## 🛑 4. Pre-Commit Hooks & Git Discipline

Automated gates must be respected:

- **Strictly No Bypassing Hooks:** It is **strictly forbidden** to bypass Git hooks. Under no circumstance should you run Git commands with `--no-verify`. If a hook fails, you must diagnose, fix, and rerun the hook until it passes.
- **Verification Command:** Before submitting work or claiming a task is done, run local linting and testing commands (e.g., `mise exec lefthook -- lefthook run pre-commit`) to guarantee your changes comply with repo guidelines.
- **Conventional Commits:** You must format every commit message according to the Conventional Commits specification.
  - _Examples:_ `feat(gcp): add compute engine instance`, `fix(unifi): update dhcp leases sops secret`.
- **Trunk-Based Development:** Create short-lived feature branches, running CI, and merging to `main` locally or via PRs with squash-merging.
- **Branch Naming:** All task branches must be named following the pattern: `<type>/<scope>/<short-desc>` (e.g., `feat/gcp/state-bucket`).
- **Plan File Location:** All plan files should be stored at: `docs/plans` (e.g., `docs/plans/2026-06-01-short-plan-name.md`).
- **Git Worktrees Mandatory:** When running tasks that add, update, or delete files, you **must** use isolated git worktrees rather than modifying the main workspace directly. Consult the `.agent/skills/using-git-worktrees/SKILL.md` skill for the proper directory selection and setup process.

---

## 📋 5. Self-Review and Task Verification

- **Mandatory Test Coverage for Added/Changed Scope:** Any added, updated, or expanded functionality, configuration, script, or infrastructure scope **must** include corresponding automated tests (e.g., Bats unit tests in `tests/scripts/`, OpenTofu native tests in `infrastructure/<module>/tests/*.tftest.hcl`, or Molecule scenarios in `configuration/roles/*/molecule/`). Never declare a feature or scope complete without accompanying automated tests verifying its correctness.

Before claiming a task is complete, verify your work:

1.  **Run local lint and tests** on changed files. Use the correct tool for the domain:
    - **OpenTofu changes:** `mise exec -- tofu fmt -check` · `mise exec -- tflint --recursive` · `mise exec -- tofu validate` (per module) · `mise run test:infra` (native `tofu test` suites)
    - **Ansible changes:** `mise exec -- ansible-lint configuration/` · Molecule test suites:
      - `(cd configuration/roles/base_ubuntu_server && mise exec -- molecule test)`
      - `(cd configuration/roles/restic_backup && mise exec -- molecule test)`
      - `(cd configuration && mise exec -- molecule test -s oci)`
    - **Script changes:** `mise exec -- shellcheck scripts/*.sh` · `mise exec -- bats tests/scripts/`
    - **Python changes:** `uv run ruff check` · `uv run ruff format --check`
    - **Pre-commit gate (all changes):** `mise exec lefthook -- lefthook run pre-commit`
    > **Note:** Current Molecule tests target Ubuntu Server 26.04 via the Docker driver across the three scenarios above (`base_ubuntu_server`, `restic_backup`, and `oci`).
2.  **Verify exit status** — all commands above must exit 0 before proceeding.
3.  **Perform a self-review diff** of your modifications to ensure no stray code, unused variables, or comments remain.
4.  **Update the task tracker** located at `docs/plans/task.md` with progress.
