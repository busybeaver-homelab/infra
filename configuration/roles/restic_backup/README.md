# restic_backup

Ansible role for configuring automated, encrypted, and deduplicated nightly backups using Restic with S3-compatible object storage (e.g., OCI Object Storage and Cloudflare R2) on Ubuntu Server 26.04 LTS.

## Features

- **Dual-Target Backups:** Supports concurrent or sequential dual-target backups (Primary OCI Object Storage and Secondary Cloudflare R2 Disaster Recovery).
- **Subshell Environment Isolation:** Target credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE`) are loaded within isolated subshells to prevent credential bleed between cloud providers.
- **Client-Side Encryption:** All backups are encrypted using AES-256 before transmission to object storage, with independent passwords supported per target.
- **Deduplication & Incremental Backups:** Restic handles deduplication and delta snapshots natively.
- **Granular Snapshot Tagging:** Snapshots are tagged with `scheduled` and their respective target label (`primary`, `secondary`).
- **Hardened Systemd Integration:** Service runs as an isolated systemd oneshot service with extensive sandboxing (`ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, restricted syscalls, and explicit read/write paths).
- **Automated Scheduling:** Triggered via systemd timer with randomized jitter to prevent thundering herds.
- **Pre- and Post-Backup Hooks:** Supports executable hook scripts placed in `/etc/restic/hooks.d/pre.d` and `/etc/restic/hooks.d/post.d`. Post-backup hooks are guaranteed to run via an `EXIT` trap even if the backup encounters an error.
- **Automatic Auto-Initialization & Integrity Check:** Auto-initializes repositories (`restic cat config || restic init`) and runs lightweight subset data integrity verification (`restic check --read-data-subset=1%`).

## Requirements

- **Operating System:** Ubuntu 26.04 LTS (x86_64 or aarch64)
- **Privileges:** Root / `become: true`
- **Ansible:** 2.17+

## Role Variables

| Variable                                | Default                                                  | Description                                                              |
| --------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `restic_backup_repository`              | `""`                                                     | Primary Restic repository URL (e.g., `s3:<endpoint>/<bucket>/<host>`)    |
| `restic_backup_s3_access_key`           | `""`                                                     | Primary S3 Access Key ID (e.g., OCI Customer Secret Key ID)              |
| `restic_backup_s3_secret_key`           | `""`                                                     | Primary S3 Secret Access Key (e.g., OCI Customer Secret Key)             |
| `restic_backup_password`                | `""`                                                     | Strong password used for primary repository encryption                   |
| `restic_backup_secondary_enabled`       | `false`                                                  | Enable secondary disaster recovery backup target (e.g., Cloudflare R2)   |
| `restic_backup_secondary_repository`    | `""`                                                     | Secondary Restic repository URL (e.g., `s3:<endpoint>/<bucket>/<host>`)  |
| `restic_backup_secondary_s3_access_key` | `""`                                                     | Secondary S3 Access Key ID                                               |
| `restic_backup_secondary_s3_secret_key` | `""`                                                     | Secondary S3 Secret Access Key                                           |
| `restic_backup_secondary_password`      | `""`                                                     | Strong password used for secondary repository encryption                 |
| `restic_backup_healthchecks_ping_url`   | `""`                                                     | Healthchecks.io ping URL for backup run heartbeat reporting              |
| `restic_backup_paths`                   | `["/etc", "/root", "/usr/local/etc", "/opt/containers"]` | Paths to include in the backup                                           |
| `restic_backup_excludes`                | `["*.log", "*.tmp", "*.bak", ...]`                       | Patterns to exclude from backups                                         |
| `restic_backup_keep_daily`              | `3`                                                      | Number of daily snapshots to retain                                      |
| `restic_backup_keep_weekly`             | `1`                                                      | Number of weekly snapshots to retain                                     |
| `restic_backup_keep_monthly`            | `0`                                                      | Number of monthly snapshots to retain                                    |
| `restic_backup_credstore_dir`           | `"/etc/credstore.encrypted"`                             | Directory for systemd encrypted credentials (`LoadCredentialEncrypted=`) |
| `restic_backup_credential_key`          | `"host"`                                                 | Key the credentials are bound to (`host`, `tpm2`, `host+tpm2`, `auto`)   |
| `restic_backup_libexec_dir`             | `"/usr/local/libexec/restic-backup"`                     | Location of the credential-sync and Healthchecks notify helpers          |
| `restic_backup_schedule_calendar`       | `"*-*-* 03:00:00 UTC"`                                   | Systemd OnCalendar schedule                                              |
| `restic_backup_random_delay_sec`        | `1800`                                                   | Systemd RandomizedDelaySec                                               |
| `restic_backup_cache_dir`               | `"/var/cache/restic"`                                    | Local cache directory                                                    |
| `restic_backup_log_dir`                 | `"/var/log/restic"`                                      | Local log directory                                                      |
| `restic_backup_config_dir`              | `"/etc/restic"`                                          | Directory for configuration and hooks                                    |
| `restic_backup_runner_script_path`      | `"/usr/local/sbin/restic-backup-runner.sh"`              | Path to the runner script                                                |

## Example Playbook

```yaml
- hosts: oci_instances
  become: true
  roles:
    - role: restic_backup
      vars:
        # Primary Target (OCI Object Storage)
        restic_backup_repository: "s3:{{ oci_restic.s3_endpoint }}/{{ oci_restic.bucket }}/{{ inventory_hostname }}"
        restic_backup_s3_access_key: "{{ oci_restic.s3_access_key_id }}"
        restic_backup_s3_secret_key: "{{ oci_restic.s3_secret_access_key }}"
        restic_backup_password: "{{ oci_restic.password }}"

        # Secondary DR Target (Cloudflare R2)
        restic_backup_secondary_enabled: true
        restic_backup_secondary_repository: "s3:{{ cloudflare_restic.s3_endpoint }}/{{ cloudflare_restic.bucket }}/{{ inventory_hostname }}"
        restic_backup_secondary_s3_access_key: "{{ cloudflare_restic.s3_access_key_id }}"
        restic_backup_secondary_s3_secret_key: "{{ cloudflare_restic.s3_secret_access_key }}"
        restic_backup_secondary_password: "{{ cloudflare_restic.password }}"
```

## Security & Secrets

All credentials are supplied from the canonical SOPS files (`secrets/credentials.sops.yaml` for production, `secrets/credentials.ci.sops.yaml` for CI and Molecule) through group variables.

Secrets (repository passwords, S3 secret keys, the Healthchecks ping URL) are stored as **systemd encrypted credentials**:

- `restic-credential-sync` encrypts each secret from stdin with `systemd-creds encrypt --with-key=host` into `/etc/credstore.encrypted/<name>` (`0400 root:root`, AES-256-GCM, bound to the host key `/var/lib/systemd/credential.secret`). It only re-encrypts when the value changed, so runs stay idempotent.
- The units load them with `LoadCredentialEncrypted=`; systemd decrypts them only into the service's private `$CREDENTIALS_DIRECTORY` at start. Credentials survive reboots and never exist in plaintext on disk.
- `/etc` is part of the backup set, so backups contain only the ciphertext. The host key in `/var/lib/systemd` is not backed up, which keeps backed-up credentials undecryptable.
- Root on the running host can still decrypt the credentials, which is true of every host-side secret delivery. On hosts with a TPM2 chip, set `restic_backup_credential_key: host+tpm2` to also bind them to the hardware.
- The Healthchecks ping URL is passed to curl via stdin (`--config -`), never as a process argument.
- Non-sensitive configuration stays in `/etc/restic` (`0600 root:root`): `backup.env`, `primary.env`, `secondary.env`.
- Legacy plaintext files (`/etc/restic/password*`) and the former tmpfs copies (`/run/secrets/*`) are removed on every run.
