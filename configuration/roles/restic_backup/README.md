# restic_backup

Ansible role for configuring automated, encrypted, and deduplicated nightly backups using Restic with S3-compatible object storage (e.g., OCI Object Storage) on Ubuntu Server 26.04 LTS.

## Features

- **Client-Side Encryption:** All backups are encrypted using AES-256 before transmission to object storage.
- **Deduplication & Incremental Backups:** Restic handles deduplication and delta snapshots natively.
- **Hardened Systemd Integration:** Service runs as an isolated systemd oneshot service with extensive sandboxing (`ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, restricted syscalls, and explicit read/write paths).
- **Automated Scheduling:** Triggered via systemd timer with randomized jitter to prevent thundering herds.
- **Pre- and Post-Backup Hooks:** Supports executable hook scripts placed in `/etc/restic/hooks.d/pre.d` and `/etc/restic/hooks.d/post.d`. Post-backup hooks are guaranteed to run via an `EXIT` trap even if the backup encounters an error.
- **Automatic Pruning & Integrity Check:** Enforces snapshot retention (`--keep-daily 3 --keep-weekly 1`) and runs lightweight subset data integrity verification (`restic check --read-data-subset=1%`).

## Requirements

- **Operating System:** Ubuntu 26.04 LTS (x86_64 or aarch64)
- **Privileges:** Root / `become: true`
- **Ansible:** 2.17+

## Role Variables

| Variable                           | Default                                                  | Description                                                        |
| ---------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------ |
| `restic_backup_repository`         | `""`                                                     | Full Restic repository URL (e.g., `s3:<endpoint>/<bucket>/<host>`) |
| `restic_backup_s3_access_key`      | `""`                                                     | S3 Access Key ID (e.g., OCI Customer Secret Key ID)                |
| `restic_backup_s3_secret_key`      | `""`                                                     | S3 Secret Access Key (e.g., OCI Customer Secret Key)               |
| `restic_backup_password`           | `""`                                                     | Strong password used for client-side repository encryption         |
| `restic_backup_paths`              | `["/etc", "/root", "/usr/local/etc", "/opt/containers"]` | Paths to include in the backup                                     |
| `restic_backup_excludes`           | `["*.log", "*.tmp", "*.bak", ...]`                       | Patterns to exclude from backups                                   |
| `restic_backup_keep_daily`         | `3`                                                      | Number of daily snapshots to retain                                |
| `restic_backup_keep_weekly`        | `1`                                                      | Number of weekly snapshots to retain                               |
| `restic_backup_keep_monthly`       | `0`                                                      | Number of monthly snapshots to retain                              |
| `restic_backup_schedule_calendar`  | `"*-*-* 03:00:00 UTC"`                                   | Systemd OnCalendar schedule                                        |
| `restic_backup_random_delay_sec`   | `1800`                                                   | Systemd RandomizedDelaySec                                         |
| `restic_backup_cache_dir`          | `"/var/cache/restic"`                                    | Local cache directory                                              |
| `restic_backup_log_dir`            | `"/var/log/restic"`                                      | Local log directory                                                |
| `restic_backup_config_dir`         | `"/etc/restic"`                                          | Directory for configuration and hooks                              |
| `restic_backup_runner_script_path` | `"/usr/local/sbin/restic-backup-runner.sh"`              | Path to the runner script                                          |

## Example Playbook

```yaml
- hosts: oci_instances
  become: true
  roles:
    - role: restic_backup
      vars:
        restic_backup_repository: "s3:{{ oci_restic.s3_endpoint }}/{{ oci_restic.bucket }}/{{ inventory_hostname }}"
        restic_backup_s3_access_key: "{{ oci_restic.s3_access_key_id }}"
        restic_backup_s3_secret_key: "{{ oci_restic.s3_secret_access_key }}"
        restic_backup_password: "{{ oci_restic.password }}"
```

## Security & Secrets

All credentials should be supplied via SOPS-encrypted group variables (`secrets/credentials.sops.yaml` for production or `secrets/credentials.ci.sops.yaml` for testing/CI). The generated environment file `/etc/restic/backup.env` is restricted to mode `0600 root:root`.
