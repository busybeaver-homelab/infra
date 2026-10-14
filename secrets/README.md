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

### Where the Passphrase Comes From

Every root module declares `state_encryption_passphrase` in `variables.tf` with **no default**. It must be at least 32 characters and must not look like a placeholder. A missing or weak value fails `init`, `plan` and `apply` instead of silently encrypting state with a key published in this repository (R2-TF-01).

There are exactly two sources:

1. `TF_VAR_state_encryption_passphrase`, if it is already set in your shell. It is preserved unchanged.
2. Production SOPS, `secrets/credentials.sops.yaml`, key `opentofu.state_encryption_passphrase`. `scripts/bootstrap-state-backend.sh` and the local drift scripts resolve it from there.

There is no local passphrase file and no module default. Tests set a synthetic value in their `variables {}` block, and CI validation uses a fixed throwaway value (see below).

### Generating the Passphrase (First Setup Only)

Generate it straight into SOPS, so it is never printed or written to disk:

```bash
openssl rand -hex 32 | jq -R . | sops set --value-stdin secrets/credentials.sops.yaml '["opentofu"]["state_encryption_passphrase"]'
```

Export it before running `tofu` by hand:

```bash
export TF_VAR_state_encryption_passphrase="$(sops -d --extract '["opentofu"]["state_encryption_passphrase"]' secrets/credentials.sops.yaml)"
```

### GitHub Actions and the State Passphrase

CI **never** receives the production state passphrase. Validate and test jobs only use a fixed throwaway value (`ci-validation-dummy-passphrase-32ch`), because they never touch real state. `infrastructure/github` enforces this with validations that reject passphrase-like secrets in any GitHub environment.

The `ci` environment receives exactly **one** age identity, the CI key that decrypts only `secrets/credentials.ci.sops.yaml`. Its source is production SOPS (`github.ci_age_key`); there is no keyring-file read and no decoy fallback. One-time setup, run in your own terminal (never in an agent session):

```bash
# Find the identity whose public key matches the CI recipient in .sops.yaml, then
# store only that identity in production SOPS. Nothing is printed.
ci_pub="$(yq '.creation_rules[0].key_groups[0].age[0]' .sops.yaml)"
while read -r key; do
  if [ "$(printf '%s\n' "$key" | age-keygen -y)" = "$ci_pub" ]; then
    printf '%s' "$key" | jq -Rs . | sops set --value-stdin secrets/credentials.sops.yaml '["github"]["ci_age_key"]'
  fi
done < <(grep '^AGE-SECRET-KEY-1' ~/.config/sops/age/keys.txt)
# Schema parity: the CI file needs the same key path with a synthetic value.
age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY-1' | tr -d '\n' | jq -Rs . | \
  sops set --value-stdin secrets/credentials.ci.sops.yaml '["github"]["ci_age_key"]'
```

Then `tofu apply` in `infrastructure/github` (owner-confirmed). This deletes the `TOFU_ENCRYPTION_PASSPHRASE` secret from the `ci` environment and replaces `SOPS_AGE_KEY_CI` with the single identity. Check with `gh secret list --env ci --repo <owner>/<repo>`.

### Rotating the State Passphrase

Rotate after any suspected exposure. That includes the period when the passphrase sat in the GitHub `ci` environment.

**How it works.** OpenTofu stores the pbkdf2 salt in the state metadata under the key provider's **name** (`key_provider.pbkdf2.<name>`). A `fallback` can only decrypt state under the name that wrote it, so the old passphrase keeps the old name and the new passphrase needs a new name. Renaming a provider without this two-step is itself a rotation and locks you out.

`scripts/rotate-state-passphrase.sh` does the whole module-level procedure. For each module, it:

1. reads the state through the old name (fallback);
2. pushes it back encrypted under the next name (`state_passphrase` → `state_passphrase_v2` → `state_passphrase_v3` …) with `state pull | state push -`. This needs only the R2 backend credentials: no provider credentials, no refresh, and serial and lineage stay unchanged. The plaintext state stays in memory;
3. proves that the new passphrase alone can read the state;
4. renames the provider in `infrastructure/<module>/encryption.tf`.

A wrong passphrase fails closed: nothing is pushed and nothing is renamed.

Run the procedure yourself, in your own terminal (never in an agent session), on a branch such as `chore/opentofu/rotate-state-passphrase`:

```bash
# 1. Keep the current passphrase as "previous", then generate the new one. Nothing is printed.
#    Add a synthetic _previous key to the CI file too (schema parity).
sops -d --extract '["opentofu"]["state_encryption_passphrase"]' secrets/credentials.sops.yaml | jq -Rs 'rtrimstr("\n")' |
  sops set --value-stdin secrets/credentials.sops.yaml '["opentofu"]["state_encryption_passphrase_previous"]'
openssl rand -hex 32 | jq -R . |
  sops set --value-stdin secrets/credentials.sops.yaml '["opentofu"]["state_encryption_passphrase"]'
openssl rand -hex 32 | jq -R . |
  sops set --value-stdin secrets/credentials.ci.sops.yaml '["opentofu"]["state_encryption_passphrase_previous"]'

# 2. Export both passphrases and the R2 backend access from SOPS (environment only, never argv).
s() { sops -d --extract "$1" secrets/credentials.sops.yaml; }
export TF_VAR_state_encryption_passphrase="$(s '["opentofu"]["state_encryption_passphrase"]')"
export TF_VAR_state_encryption_passphrase_previous="$(s '["opentofu"]["state_encryption_passphrase_previous"]')"
export AWS_ACCESS_KEY_ID="$(s '["opentofu"]["cloudflare_r2_access_key_id"]')"
export AWS_SECRET_ACCESS_KEY="$(s '["opentofu"]["cloudflare_r2_secret_access_key"]')"
export TOFU_BACKEND_ENDPOINT="https://$(s '["cloudflare"]["account_id"]').r2.cloudflarestorage.com"

# 3. Re-encrypt every module's remote state and rename its key provider (asks for confirmation).
mise exec -- scripts/rotate-state-passphrase.sh --all

# 4. Every module must now plan with the new passphrase alone.
unset TF_VAR_state_encryption_passphrase_previous
```

Then:

5. Commit the renamed `encryption.tf` files immediately and merge them, since `main` can no longer read the state under the old name. A local fast-forward merge by the owner is fine.
6. Remove `opentofu.state_encryption_passphrase_previous` from both SOPS files (`sops unset`).

If the script stops partway, the modules it already rotated have the new provider name in `encryption.tf`. The others are unchanged. Re-run it for the remaining modules only.

> **WARNING:** Losing the passphrase makes all encrypted state files permanently
> unrecoverable. Keep at least one secure backup (e.g., a password manager entry).

---

## 📦 Canonical Secret Keys Inventory

All sensitive configuration parameters are strictly encapsulated in the two canonical files (`secrets/credentials.sops.yaml` for production and `secrets/credentials.ci.sops.yaml` for CI). Both files enforce 100% schema parity.

### OpenTofu State & Cloudflare Backend Credentials

| Secret Key                                 | Description                                                                      | Sourced By                                                                                                          |
| ------------------------------------------ | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `opentofu.cloudflare_r2_access_key_id`     | Cloudflare R2 API Token Access Key ID for S3 remote state backend                | `scripts/bootstrap-state-backend.sh`, `.github/workflows/drift-detection.yml`                                       |
| `opentofu.cloudflare_r2_secret_access_key` | Cloudflare R2 API Token Secret Access Key for S3 remote state backend            | `scripts/bootstrap-state-backend.sh`, `.github/workflows/drift-detection.yml`                                       |
| `opentofu.state_encryption_passphrase`     | OpenTofu client-side AES-GCM-256 state encryption passphrase (no module default) | `scripts/bootstrap-state-backend.sh`, `scripts/rotate-state-passphrase.sh`, `.github/workflows/drift-detection.yml` |

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

### NextDNS Credentials & Configuration Data (`nextdns`)

Multi-account NextDNS credentials and profile configuration consumed by `infrastructure/dns` via `data.sops_file`.
Map keys (`account_1`..`account_4`) are generic and non-identifying (SOPS does not encrypt YAML keys). CI holds decoy leaves with identical key paths.

| Key                                                                                       | Description                                                                           |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `nextdns.accounts.<account_key>.api_key`                                                  | Per-account NextDNS API key (`account_1`..`account_4`)                                |
| `nextdns.accounts.<account_key>.account_name`                                             | Encrypted human-readable account label                                                |
| `nextdns.accounts.<account_key>.profile_id`                                               | Encrypted 6-character NextDNS profile ID                                              |
| `nextdns.accounts.<account_key>.profile_name`                                             | Encrypted human-readable NextDNS profile name                                         |
| `nextdns.config.shared.rewrites[].{name,content}`                                         | Shared split-horizon DNS rewrites (`name` -> `content`) applied across all 4 accounts |
| `nextdns.config.shared.allowlist[].{id,active}`                                           | Shared allowlist entries applied across all 4 accounts                                |
| `nextdns.config.shared.denylist[].{id,active}`                                            | Shared denylist entries applied across all 4 accounts                                 |
| `nextdns.config.overrides.<account_key>.extra_rewrites[]`                                 | Per-account additive split-horizon DNS rewrites                                       |
| `nextdns.config.overrides.<account_key>.excluded_rewrite_names`                           | Per-account list of shared rewrite `name` values to omit                              |
| `nextdns.config.overrides.<account_key>.extra_{allowlist,denylist,blocklists,natives}`    | Per-account additive allowlist/denylist/blocklist/native entries                      |
| `nextdns.config.overrides.<account_key>.excluded_{allowlist,denylist,blocklists,natives}` | Per-account excluded shared allowlist/denylist/blocklist/native entries               |
| `nextdns.config.overrides.<account_key>.{security,privacy,parental_control,settings}`     | Per-account posture overrides (`null` inherits baseline)                              |

### Host Secret Delivery (systemd Encrypted Credentials)

Service secrets on hosts (restic repository passwords, S3 secret keys, the Healthchecks ping URL) are delivered without plaintext on disk and survive reboots:

1. **Source of truth:** values stay in the canonical SOPS files. Ansible decrypts them on the controller (`community.sops`) as before.
2. **Encrypted at rest on the host:** the `restic_backup` role pipes each secret through stdin into `systemd-creds encrypt --with-key=host`, writing `/etc/credstore.encrypted/<name>` (`0400 root:root`, AES-256-GCM, bound to the root-only host key `/var/lib/systemd/credential.secret`). It only re-encrypts when a value changed.
3. **Decrypted per service:** units use `LoadCredentialEncrypted=<name>:/etc/credstore.encrypted/<name>`. systemd decrypts into the service's private `$CREDENTIALS_DIRECTORY` at start, and the process reads `$CREDENTIALS_DIRECTORY/<name>`. Nothing goes into `EnvironmentFile=`, argv or `/run/secrets`.
4. **Backups:** `/etc` is backed up, so backups contain only ciphertext. The host key in `/var/lib/systemd` is excluded, so a leaked backup does not expose the credentials.
5. **Limits:** root on the running host can decrypt the credentials, as with any host-side delivery. A boot-volume copy contains both the ciphertext and the host key. Binding to a TPM2 chip (`--with-key=host+tpm2`) would close that gap, but Always Free shapes (`VM.Standard.A1.Flex`, `VM.Standard.E2.1.Micro`) do not support Shielded Instances / vTPM.
6. **Rotation:** change the value in SOPS and re-run Ansible; the next service start uses the new credential.

The earlier OCI Vault boot-fetch design (`docs/plans/2026-10-13-oci-vault-secrets-and-systemd-credentials-design.md`) was retired in favour of this approach; see `docs/plans/2026-10-13-systemd-creds-secret-delivery-design.md`.

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
