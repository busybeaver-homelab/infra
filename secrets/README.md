# Secrets Management & SOPS Configuration Guide

This repository uses **SOPS (Secrets OPerations Suite)** for encrypting sensitive files such as OpenTofu/Terraform variables and Ansible host vars. Admin/production secrets are encrypted with **GPG**, while CI/CD uses **age** decoy keys.

---

## 🔑 Decoy/CI Testing Keys

Below are the **decoy age keys** generated for CI/CD testing, local evaluation, and dry-runs. These are completely public and committed to the repository for convenience in non-production environments.

> [!WARNING]
> **NEVER** use these decoy keys for real production systems. They are public and insecure.

### CI/CD Environment Key (Decoy CI Actions)

- **Public Key:** `age1e0pws4km4hd9ecasjlscn9d5kzsz69fuxdn5udf57wgktjz3jcnsjz8gvr`
- **Private Key:** Generated locally at `~/.config/sops/age/keys.txt` and injected via GitHub Actions secret `SOPS_AGE_KEY`. Plaintext keys are strictly forbidden in this repository.

---

## 💻 Local Setup (Admins Only)

To decrypt and manage production files locally, you must have the production GPG private key available in your local keyring.

1. **Import the production GPG key:**
   Request the private key from a current admin and import it:

   ```bash
   mise exec -- gpg --import /path/to/production-private-key.asc
   ```

2. **Import the production backup public key:**
   This allows you to encrypt new secrets to the production key:

   ```bash
   mise exec -- gpg --import secrets/gpg-production-backup.pub
   ```

3. **Verify the key is available:**
   ```bash
   mise exec -- gpg --list-keys 5EE1590FF82DC2A3829D224FAA73ACF495CC009D
   ```

---

## 🛟 Offline Disaster Recovery & Emergency Decryption

Production secrets (`secrets/credentials.sops.yaml`) are multi-recipient encrypted to both the primary admin GPG key and a **secondary offline Age recovery key**.

- **Public Key:** `age15vgve3yy0m2k9mqca9ntc8zt235ruf3nxnnacce2evl2ncz68u3q5uf9jq`
- **Key Storage:** The corresponding private key is stored **offline only** on an encrypted hardware security token (YubiKey) and a paper backup stored in a physical fireproof safe. It is **never** stored on an internet-connected device or committed to version control.

### Generating a New Offline Recovery Keypair

If rotating the recovery key:

```bash
# On an air-gapped machine:
mise exec -- age-keygen -o /tmp/recovery-age-key.txt
# Public key is printed to stderr/header; copy public key to .sops.yaml
# Print or transfer private key to hardware token / safe paper backup
# Securely shred the temporary file:
shred -u /tmp/recovery-age-key.txt
```

### Break-Glass Disaster Recovery Procedure

If the primary GPG key is lost, corrupted, or inaccessible during an emergency:

1. Retrieve the physical paper backup or hardware security token from the safe.
2. Export the offline recovery key into a strictly ephemeral, restricted subshell:
   ```bash
   read -rs OFFLINE_KEY # type or paste private key safely
   SOPS_AGE_KEY="$OFFLINE_KEY" mise exec -- sops -d secrets/credentials.sops.yaml > /tmp/recovered-credentials.yaml
   unset OFFLINE_KEY
   ```
3. Generate a new primary administrative keypair, update `.sops.yaml`, re-encrypt the credentials file, and securely wipe `/tmp/recovered-credentials.yaml`.

---

## 🚀 GitHub Actions Secret Injection

To run automated checks (like Ansible syntax tests or OpenTofu validations) against encrypted decoy configuration files in CI/CD pipelines, you must inject the private key safely via **GitHub Secrets**.

### Step 1: Add the Secret to GitHub

1. In your GitHub repository, navigate to **Settings > Secrets and variables > Actions**.
2. Click **New repository secret**.
3. Configure the secret:
   - **Name:** `SOPS_AGE_KEY`
   - **Secret:** _(Paste the private key from `~/.config/sops/age/keys.txt`)_
     ```text
     <paste-contents-of-~/.config/sops/age/keys.txt>
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
git config diff.sops.textconv "mise exec -- sops --decrypt"
```

This is a local-only git config — it is never committed. It lets `git diff` pipe
SOPS files through `sops --decrypt` via mise before displaying the diff.

---

## 🔐 OpenTofu State Encryption Passphrase

OpenTofu state files are encrypted at rest using AES-GCM-256 with a PBKDF2-derived key.
The passphrase is **never committed** — it lives only on your local machine and in GitHub Secrets.

### Local Setup (One-Time)

Run `mise exec -- ./scripts/bootstrap.sh` — it auto-generates a passphrase at
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
