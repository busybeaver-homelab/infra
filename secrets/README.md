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

## 🛟 Disaster Recovery & Emergency Decryption

Production secrets (`secrets/credentials.sops.yaml`) are multi-recipient encrypted to both the primary admin GPG key and a **secondary Age recovery key**.

- **Public Key:** `age136vdv2svv5lm53um9yvgw2f6uq87ce2cgcr2n54s32mpwlseh4cqsjsdlv`
- **Key Storage:** The corresponding private key is stored **offline, encrypted only**. It is **never** committed to version control.

### Generating a New Recovery Keypair

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
2. Export the recovery key into a strictly ephemeral, restricted subshell:
   ```bash
   read -rs RECOVERY_KEY # type or paste private key safely
   SOPS_AGE_KEY="$RECOVERY_KEY" mise exec -- sops -d secrets/credentials.sops.yaml > /tmp/recovered-credentials.yaml
   unset RECOVERY_KEY
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
The passphrase is **never committed in plaintext** — it is encrypted within SOPS (`secrets/credentials.sops.yaml` for production, `secrets/credentials.ci.sops.yaml` for CI) or resolved via the hierarchy below.

### Resolution Hierarchy

When running `scripts/bootstrap-state-backend.sh` or automated workflows, the passphrase is resolved using the following 4-tier precedence:

1. **Tier 1 (Explicit Environment Variable):** `TF_VAR_state_encryption_passphrase` (if already set in your shell environment, it is preserved without modification).
2. **Tier 2 (Canonical SOPS Secret - Recommended):** Auto-resolved from `secrets/credentials.sops.yaml` (key: `opentofu.state_encryption_passphrase`).
3. **Tier 3 (Local File Fallback):** Read from `~/.config/homelab-infra/tofu-passphrase` (created during initial setup).
4. **Tier 4 (Module Default):** Built-in fallback defined in `infrastructure/modules/cloud_dns/encryption.tf` (`homelab-state-encryption-passphrase-default`).

### Generating a Secure Passphrase for Production

To generate a cryptographically strong 32-character passphrase and save it to your production SOPS vault:

```bash
# 1. Generate a secure 32-character alphanumeric passphrase
PASSPHRASE=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

# 2. Store it in canonical production SOPS secrets via mise
mise run secret:prod:set "opentofu.state_encryption_passphrase"
# (Paste or enter the generated passphrase when prompted)

# 3. (Optional) Mirror to local fallback file for offline access:
mkdir -p ~/.config/homelab-infra
printf "%s" "$PASSPHRASE" > ~/.config/homelab-infra/tofu-passphrase
chmod 600 ~/.config/homelab-infra/tofu-passphrase
unset PASSPHRASE
```

### GitHub Actions Setup

In CI workflows, the passphrase can be resolved directly from `secrets/credentials.ci.sops.yaml` using `SOPS_AGE_KEY`, or injected as an explicit repository secret `TOFU_ENCRYPTION_PASSPHRASE`.

> **WARNING:** Losing the passphrase makes all encrypted state files permanently
> unrecoverable. Keep at least one secure backup (e.g., a password manager entry).

---

## 📦 Canonical Secret Keys Inventory

All sensitive configuration parameters are strictly encapsulated in the two canonical files (`secrets/credentials.sops.yaml` for production and `secrets/credentials.ci.sops.yaml` for CI). Both files enforce 100% schema parity.

### OpenTofu State & Cloudflare Backend Credentials

| Secret Key                                 | Description                                                           | Sourced By                                                                    |
| ------------------------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `opentofu.cloudflare_r2_access_key_id`     | Cloudflare R2 API Token Access Key ID for S3 remote state backend     | `scripts/bootstrap-state-backend.sh`, `.github/workflows/drift-detection.yml` |
| `opentofu.cloudflare_r2_secret_access_key` | Cloudflare R2 API Token Secret Access Key for S3 remote state backend | `scripts/bootstrap-state-backend.sh`, `.github/workflows/drift-detection.yml` |
| `opentofu.state_encryption_passphrase`     | OpenTofu client-side AES-GCM-256 state encryption passphrase          | `scripts/bootstrap-state-backend.sh`, `.github/workflows/drift-detection.yml` |

To set or update production credentials:

```bash
mise run secret:prod:set "opentofu.cloudflare_r2_access_key_id"
mise run secret:prod:set "opentofu.cloudflare_r2_secret_access_key"
mise run secret:prod:set "opentofu.state_encryption_passphrase"
```

To set or update CI decoy credentials:

```bash
mise run secret:ci:set "opentofu.cloudflare_r2_access_key_id"
mise run secret:ci:set "opentofu.cloudflare_r2_secret_access_key"
mise run secret:ci:set "opentofu.state_encryption_passphrase"
```

### Cloudflare Configuration Data (`cloudflare.config`)

Identifying Cloudflare configuration consumed by `infrastructure/cloudflare` via `data.sops_file`.
Map keys are logical and non-identifying (SOPS does not encrypt keys). CI holds decoy leaves with identical key paths.

| Key                                                         | Description                                                                                           |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `cloudflare.config.account_name`                            | Account display name                                                                                  |
| `cloudflare.config.notification_email`                      | Recipient for notification policies                                                                   |
| `cloudflare.config.notification_policy_ids.<alert_type>`    | Notification policy IDs (import)                                                                      |
| `cloudflare.config.email_destinations.<dest_n>.{id,email}`  | Email Routing destination addresses                                                                   |
| `cloudflare.config.zero_trust.*`                            | Access org (name, auth domain, login design), OTP IdP ID, default DNS location, split-tunnel excludes |
| `cloudflare.config.iam.tokens.<key>.{id,policies[]}`        | Frozen token IDs and policies (`effect`, `resources`, `permission_groups` as `name\|scopes`)          |
| `cloudflare.config.iam.member.{id,email,resource_group_id}` | Frozen account member                                                                                 |
| `cloudflare.config.zones.<zone_key>.*`                      | Zone name/ID, DNS records, Email Routing rules and catch-all, WAF custom rules                        |

### OCI Vault Secrets & Zero-Trust Host Delivery

To achieve zero-trust cloud secrets delivery without persistent disk storage or long-lived API tokens:

1. **Always Free Cloud Vault:** OCI Standard Virtual Vault (`vault_type = "DEFAULT"`) with software AES-256 key (`protection_mode = "SOFTWARE"`). Both standard vaults and software keys are 100% free under OCI Always Free tier (up to 20 secrets per tenancy at $0 cost).
2. **Instance Principal IAM:** Compute instances authenticate automatically to OCI Vault via IMDSv2 and Instance Principals using dynamic group `homelab-oci-vms` matching `instance.compartment.id = '<compartment_ocid>'`. IAM policy grants `read secret-bundles in compartment` strictly to this dynamic group.
3. **In-Memory Early Boot Delivery (`/run/secrets`):** Systemd oneshot unit `oci-secrets-fetch.service` executes `/usr/local/sbin/oci-fetch-secrets.sh` on boot, querying secret bundles directly into volatile `tmpfs` `/run/secrets/` (permissions `0700 root:root` directory, `0400 root:root` files). Secrets exist only in RAM and vanish on shutdown.
4. **Modern systemd `LoadCredential=`:** Host systemd units (such as `restic_backup`) bind secrets into isolated process sandboxes using `LoadCredential=<name>:/run/secrets/<file>`. The unit accesses them securely via `$CREDENTIALS_DIRECTORY` without reading `/run/secrets/` directly or leaking credentials into `/proc`, disk, or environment tables.
5. **Container Isolation:** Docker and non-systemd workloads consume `/run/secrets/` via read-only volume mounts (`-v /run/secrets:/run/secrets:ro`).

---

## 🔐 Docs & Backups Transparent Encryption (git-crypt)

All internal architectural designs, operational plans, task trackers, and documentation under `docs/`, as well as configuration backups and recovery archives under `backups/`, are encrypted at rest in Git using [git-crypt](https://github.com/AGWA/git-crypt) to eliminate the risk of sensitive homelab topology, configuration, or credentials leakage via public/remote repositories.

### Key Management & GPG Association

- **Single GPG Key Standard:** `docs/` and `backups/` are encrypted with the **identical production GPG key** used for `secrets/credentials.sops.yaml` (`5EE1590FF82DC2A3829D224FAA73ACF495CC009D`). No separate or ad-hoc keys are maintained.
- **CI Decoupling:** Documentation and backup files are not required during continuous integration pipelines (GitHub Actions). CI runners execute without production GPG keys; linters automatically skip encrypted binary files (`\0GITCRYPT`).
- **Granular Filter:** `docs/**` and `backups/**` are encrypted via `.gitattributes`. OpenTofu HCL code, Ansible playbooks, and automated test suites remain plaintext.

### Daily Operations

#### Unlocking the Repository

If `docs/plans/archive/task-2026-10-13-legacy-consolidated-tracker.md` or `backups/README.md` appears as encrypted binary data upon cloning or pulling:

```bash
# Automated via bootstrap:
./scripts/bootstrap.sh

# Or manual unlock:
git-crypt unlock
```

#### Verifying Encryption Status

To confirm that all files in `docs/` and `backups/` are encrypted before pushing commits:

```bash
git-crypt status -e
```

All files under `docs/` and `backups/` must report `encrypted: docs/...` or `encrypted: backups/...`.

#### Locking for Security Audits / CI Testing

To test how linters and Git hooks behave when documentation and backups are locked:

```bash
git-crypt lock
```
