# restic_backup

Ansible role for configuring automated, encrypted, and deduplicated nightly backups using Restic with S3-compatible object storage (OCI Object Storage and GCP Cloud Storage via HMAC S3 interoperability) on Ubuntu Server 26.04 LTS. Secondary disaster recovery (DR) copies to Cloudflare R2 are pulled daily from the `ops` GitHub Actions environment (`.github/workflows/backup-dr-copy.yml`), so hosts hold only append-only primary repository credentials.

## Features

- **Primary Append-Only Host Backups:** Hosts write nightly snapshots to their primary provider bucket (OCI Object Storage or GCP Cloud Storage) using append-only S3 writer credentials.
- **Subshell Environment Isolation:** Target credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE`) are loaded within an isolated subshell.
- **Client-Side Encryption:** All backups are encrypted using AES-256 before transmission to object storage.
- **Deduplication & Incremental Backups:** Restic handles deduplication and delta snapshots natively.
- **Granular Snapshot Tagging:** Snapshots are tagged with `scheduled` and `primary`.
- **Hardened Systemd Integration:** Service runs as an isolated systemd oneshot service with extensive sandboxing (`ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, restricted syscalls, and explicit read/write paths).
- **Automated Scheduling:** Triggered via systemd timer with randomized jitter to prevent thundering herds.
- **Pre- and Post-Backup Hooks:** Supports executable hook scripts placed in `/etc/restic/hooks.d/pre.d` and `/etc/restic/hooks.d/post.d`. Post-backup hooks are guaranteed to run via an `EXIT` trap even if the backup encounters an error.
- **Integrity Verification:** Runs lightweight subset data integrity verification (`restic check --read-data-subset=1%`) after each snapshot; optionally auto-initializes uninitialized repositories when `restic_backup_auto_init: true`.

## Requirements

- **Operating System:** Ubuntu 26.04 LTS (x86_64 or aarch64)
- **Privileges:** Root / `become: true`
- **Ansible:** 2.17+

## Role Variables

| Variable                              | Default                                                  | Description                                                              |
| ------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `restic_backup_repository`            | `""`                                                     | Primary Restic repository URL (e.g., `s3:<endpoint>/<bucket>/<host>`)    |
| `restic_backup_s3_access_key`         | `""`                                                     | Primary S3 Access Key ID (e.g., OCI Customer Secret Key ID)              |
| `restic_backup_s3_secret_key`         | `""`                                                     | Primary S3 Secret Access Key (e.g., OCI Customer Secret Key)             |
| `restic_backup_password`              | `""`                                                     | Strong password used for primary repository encryption                   |
| `restic_backup_healthchecks_ping_url` | `""`                                                     | Healthchecks.io ping URL for backup run heartbeat reporting              |
| `restic_backup_auto_init`             | `false`                                                  | Automatically initialize repository when `restic cat config` exits 10    |
| `restic_backup_paths`                 | `["/etc", "/root", "/usr/local/etc", "/opt/containers"]` | Paths to include in the backup                                           |
| `restic_backup_excludes`              | `["*.log", "*.tmp", "*.bak", ...]`                       | Patterns to exclude from backups                                         |
| `restic_backup_credstore_dir`         | `"/etc/credstore.encrypted"`                             | Directory for systemd encrypted credentials (`LoadCredentialEncrypted=`) |
| `restic_backup_credential_key`        | `"host"`                                                 | Key the credentials are bound to (`host`, `tpm2`, `host+tpm2`, `auto`)   |
| `restic_backup_libexec_dir`           | `"/usr/local/libexec/restic-backup"`                     | Location of the credential-sync and Healthchecks notify helpers          |
| `restic_backup_schedule_calendar`     | `"*-*-* 03:00:00 UTC"`                                   | Systemd OnCalendar schedule                                              |
| `restic_backup_random_delay_sec`      | `1800`                                                   | Systemd RandomizedDelaySec                                               |
| `restic_backup_cache_dir`             | `"/var/cache/restic"`                                    | Local cache directory                                                    |
| `restic_backup_log_dir`               | `"/var/log/restic"`                                      | Local log directory                                                      |
| `restic_backup_config_dir`            | `"/etc/restic"`                                          | Directory for configuration and hooks                                    |
| `restic_backup_runner_script_path`    | `"/usr/local/sbin/restic-backup-runner.sh"`              | Path to the runner script                                                |

## Example Playbook

```yaml
- hosts: oci_instances
  become: true
  roles:
    - role: restic_backup
      vars:
        # Primary Target (OCI Object Storage — endpoint, bucket, and S3 keys from OpenTofu; password from SOPS)
        restic_backup_repository: "s3:{{ tofu_oci_restic.s3_endpoint }}/{{ tofu_oci_restic.bucket }}/{{ inventory_hostname }}"
        restic_backup_s3_access_key: "{{ tofu_oci_restic.s3_access_key_id }}"
        restic_backup_s3_secret_key: "{{ tofu_oci_restic.s3_secret_access_key }}"
        restic_backup_password: "{{ oci_restic.password }}"
        restic_backup_healthchecks_ping_url: "{{ tofu_host_backup_ping_urls[inventory_hostname] }}"
```

## Security & Secrets

Object storage endpoints, bucket names, append-only S3 writer credentials, and per-host Healthchecks ping URLs are provisioned by OpenTofu (`infrastructure/oci`, `infrastructure/gcp`, and `infrastructure/monitoring`) and loaded into memory at playbook runtime via `scripts/get-tofu-restic-vars.sh` (`tofu_oci_restic`, `tofu_gcp_restic`, `tofu_host_backup_ping_urls`, `tofu_host_alive_ping_urls`). Client-side Restic repository encryption passwords (`oci_restic.password`, `gcp_restic.password`) are supplied from the canonical SOPS files (`secrets/credentials.sops.yaml` for production, `secrets/credentials.ci.sops.yaml` for CI and Molecule) through group variables.

Secrets (repository password, S3 secret key, the Healthchecks ping URL) are stored as **systemd encrypted credentials**:

- `restic-credential-sync` encrypts each secret from stdin with `systemd-creds encrypt --with-key=host` into `/etc/credstore.encrypted/<name>` (`0400 root:root`, AES-256-GCM, bound to the host key `/var/lib/systemd/credential.secret`). It only re-encrypts when the value changed, so runs stay idempotent.
- The units load them with `LoadCredentialEncrypted=`; systemd decrypts them only into the service's private `$CREDENTIALS_DIRECTORY` at start. Credentials survive reboots and never exist in plaintext on disk.
- `/etc` is part of the backup set, so backups contain only the ciphertext. The host key in `/var/lib/systemd` is not backed up, which keeps backed-up credentials undecryptable.
- Root on the running host can still decrypt the credentials, which is true of every host-side secret delivery. On hosts with a TPM2 chip, set `restic_backup_credential_key: host+tpm2` to also bind them to the hardware.
- The Healthchecks ping URL is passed to curl via stdin (`--config -`), never as a process argument.
- Non-sensitive configuration stays in `/etc/restic` (`0600 root:root`): `backup.env`, `primary.env`.
- Legacy plaintext files (`/etc/restic/password*`), retired secondary R2 files (`/etc/restic/secondary.env`, `/etc/credstore.encrypted/restic_secondary_password`, `/etc/credstore.encrypted/cloudflare_s3_secret_key`), and the former tmpfs copies (`/run/secrets/*`) are removed on every run.
