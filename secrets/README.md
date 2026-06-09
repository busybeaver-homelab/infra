# Secrets Management & SOPS Configuration Guide

This repository uses **SOPS (Secrets OPerations Suite)** and **age** keys for encrypting sensitive files such as OpenTofu/Terraform variables and Ansible host vars.

---

## 🔑 Decoy/CI Testing Keys

Below are the **decoy keys** generated for CI/CD testing, local evaluation, and dry-runs. These are completely public and committed to the repository for convenience in non-production environments.

> [!WARNING]
> **NEVER** use these decoy keys for real production systems. They are public and insecure.

### 1. Admin Environment Key (Local Admins)
- **Public Key:** `age1tvjjrqfkhm3zwakv8cy4kk8kzhglz8yhwj3gz8tyhmawmdnfkussnvhm3w`
- **Private Key:** `AGE-SECRET-KEY-1QA35AYVMEUFTPF9809M6WNK68LHK385DUEUSLX9XGRZQN9LQXU3QRY78FS`

### 2. CI/CD Environment Key (Decoy CI Actions)
- **Public Key:** `age1znxravd7ehfaqk6reqr7tdr5wrzmx9zw7f3uyhqc9g5mt0wyxsss2jpr2v`
- **Private Key:** `AGE-SECRET-KEY-17PR87XDZLMHYWLR542HNRFPWV53GWRHA0TQ904YJ2850Q3333TSSULL055`

---

## 💻 Local Setup (Admins Only)

To decrypt and manage production files locally, you must have your own private `age` key configured:

1. **Locate or generate your key:**
   Standard key location: `~/.config/sops/age/keys.txt`
   If you do not have one, run:
   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   ```

2. **Configure your shell environment:**
   SOPS automatically looks for `SOPS_AGE_KEY_FILE`. Ensure this variable is set in your `.zshrc`, `.bashrc`, or environment:
   ```bash
   export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
   ```

3. **Import the Admin GPG Backup Key (Optional):**
   This repository includes a backup GPG public key so you can easily encrypt secrets for both keys. To import this public key into your local keyring:
   ```bash
   gpg --import secrets/gpg-production-backup.pub
   ```

---

## 🚀 GitHub Actions Secret Injection

To run automated checks (like Ansible syntax tests or OpenTofu validations) against encrypted decoy configuration files in CI/CD pipelines, you must inject the private key safely via **GitHub Secrets**.

### Step 1: Add the Secret to GitHub
1. In your GitHub repository, navigate to **Settings > Secrets and variables > Actions**.
2. Click **New repository secret**.
3. Configure the secret:
   - **Name:** `SOPS_AGE_KEY`
   - **Secret:** *(Paste the private key)*
     ```text
     AGE-SECRET-KEY-17PR87XDZLMHYWLR542HNRFPWV53GWRHA0TQ904YJ2850Q3333TSSULL055
     ```

### Step 2: Use the Secret in GitHub Actions Workflow
In your GitHub Actions workflow files (`.github/workflows/*.yml`), inject the secret as an environment variable or write it to the default path before executing SOPS/OpenTofu/Ansible tasks.

#### Option A: Inject via Env Variable (Recommended)
This is the simplest way. Pass the secret as `SOPS_AGE_KEY` directly to steps that execute OpenTofu or Ansible:

```yaml
- name: OpenTofu Plan
  run: tofu plan
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
```

#### Option B: Write Secret to File
If a tool strictly requires a physical key file on disk:

```yaml
- name: Set up SOPS Age Key
  run: |
    mkdir -p ~/.config/sops/age
    echo "${{ secrets.SOPS_AGE_KEY }}" > ~/.config/sops/age/keys.txt
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
```

---

## 🔧 Git Diff Driver Setup (One-Time, Per Developer)

To enable plaintext diffs for SOPS-encrypted files locally, run once:

```bash
git config diff.sops.textconv "sops --decrypt"
```

This is a local-only git config — it is never committed. It lets `git diff` pipe
SOPS files through `sops --decrypt` before displaying the diff.

---

## 🔐 OpenTofu State Encryption Passphrase

OpenTofu state files are encrypted at rest using AES-GCM-256 with a PBKDF2-derived key.
The passphrase is **never committed** — it lives only on your local machine and in GitHub Secrets.

### Local Setup (One-Time)

Run `scripts/bootstrap.sh` — it auto-generates a passphrase at
`~/.config/homelab-infra/tofu-passphrase` and prints the export command.

Add to your shell rc file (`~/.zshrc` or `~/.bashrc`):

```bash
export TF_VAR_state_encryption_passphrase="$(cat ~/.config/homelab-infra/tofu-passphrase)"
```

### GitHub Actions Setup

Add the passphrase as a GitHub Actions secret named `TOFU_ENCRYPTION_PASSPHRASE`.
The value is the contents of `~/.config/homelab-infra/tofu-passphrase`.

> **WARNING:** Losing the passphrase makes all encrypted state files permanently
> unrecoverable. Keep at least one secure backup (e.g., a password manager entry).
