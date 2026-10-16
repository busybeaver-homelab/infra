# `docker_compose_service` Ansible Role

Provisions the signed GitOps Docker Compose reconciler, health-gated automatic rollback engine, Healthchecks.io alerting, Docker daemon log rotation, and rollback-safe weekly image pruning on Ubuntu 26.04 LTS hosts.

## Overview

1. **Signed GitHub Release Verification:** Every 15 minutes (`homelab-compose-reconcile.timer`), the reconciler queries the latest release of [`busybeaver/homelab-services`](https://github.com/busybeaver/homelab-services), validates the release tag (`^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+$`), verifies `SHA256SUMS` against `SHA256SUMS.sigstore.json` using Sigstore `cosign` v3 and `/etc/containers/cosign.pub`, verifies the signed `RELEASE` tag binding and downgrade protection (`sort -V`), and checks the SHA-256 digest of `docker-compose.<target>.yaml`.
2. **Manifest Safety & Required Variables Gate:** Rejects manifests containing `build:` sections, relative bind mounts, disallowed `macvlan`/`ipvlan` networks or `mac_address` fields (unless `docker_compose_service_allow_macvlan: true`), or unset interpolation variables without defaults.
3. **Health-Gated Convergence & Automatic Rollback:** Deploys from `/opt/containers/releases/<tag>/docker-compose.yaml` with `--project-name` and `--env-file "${CREDENTIALS_DIRECTORY}/homelab_compose_env"`. Only flips `/opt/containers/current` and `/opt/containers/previous` **after** `up -d --wait` and `verify_stack_health` pass. If deployment fails, records the tag in `/var/lib/homelab-compose/quarantined-release`, restores `current`, and exits `1` so `OnFailure=homelab-compose-failure@%n.service` sends a `/fail` alert.
4. **Rollback-Safe Weekly Cleanup:** Every Sunday at 03:30 (`homelab-docker-cleanup.timer`), creates temporary stopped hold containers (`--pull=never`) referencing all images in `current` and `previous` before running `docker image prune --all --force --filter "until=720h"`, ensuring rollback images are never pruned. Named volumes are never pruned.

See [`docs/plans/2026-10-16-docker-compose-gitops-design.md`](../../../docs/plans/2026-10-16-docker-compose-gitops-design.md) for the full architecture and [`docs/plans/2026-10-16-homelab-services-github-releases-design.md`](../../../docs/plans/2026-10-16-homelab-services-github-releases-design.md) for the upstream release workflow contract.

## Pinned Public Key (`files/cosign.pub`)

Copied from `https://raw.githubusercontent.com/busybeaver/homelab-services/main/public_key/cosign.pub`:

- **SPKI DER SHA-256 (`openssl pkey -pubin -in cosign.pub -outform DER | sha256sum`):** `315c9654be50e744eed459ddbb58915474fdf7606435530e69bec85b69ecf7b5`
- **PEM File SHA-256 (`sha256sum cosign.pub`):** `c5905f796789e76f7a384f4acb67589d527e39e5e0566d6b7809cbcd4654e7e5`

## SOPS Schema (`secrets/credentials.sops.yaml` & `secrets/credentials.ci.sops.yaml`)

Each managed host maps 1:1 to a unique logical target ID:

```yaml
compose:
  targets:
    homelab:
      env:
        SSL_CERT_FILE: "/etc/ssl/certs/ca-certificates.crt"
        TZ: "Europe/Berlin"
        VOLUME_BASE_DIRECTORY: "/opt/container-data"
    gcp:
      env:
        TZ: "Europe/Berlin"
        VOLUME_BASE_DIRECTORY: "/opt/container-data"
    oci-1:
      env:
        TZ: "Europe/Berlin"
        VOLUME_BASE_DIRECTORY: "/opt/container-data"
  hosts:
    - host: "<inventory_hostname>"
      target: "homelab"
      healthchecks_ping_url: "https://hc-ping.com/<uuid>"
```

## Key Role Variables

| Variable                                    | Default     | Description                                                                                             |
| :------------------------------------------ | :---------- | :------------------------------------------------------------------------------------------------------ |
| `docker_compose_service_enabled`            | `false`     | Enables or disables the role on the target host (`STD-AN-29`).                                          |
| `docker_compose_service_manage_daemon_json` | `false`     | Set `true` only on hosts where `geerlingguy.docker` does not manage `/etc/docker/daemon.json`.          |
| `docker_compose_service_allow_macvlan`      | `false`     | Permits `macvlan`/`ipvlan` networks and `mac_address` fields (enabled on `homelab`, disabled on cloud). |
| `docker_compose_service_credential_key`     | `"host"`    | `systemd-creds` key mode (`"host"` on OCI/homelab, `"host+tpm2"` on GCP Shielded VMs).                  |
| `docker_compose_service_project_name`       | `"homelab"` | Fixed Docker Compose project name passed via `--project-name`.                                          |
| `docker_compose_service_wait_timeout`       | `180`       | Timeout in seconds for `docker compose up -d --wait`.                                                   |
| `docker_compose_service_keep_releases`      | `5`         | Number of verified release directories retained under `/opt/containers/releases/`.                      |
| `docker_compose_service_cosign_version`     | `"v3.1.3"`  | Renovate-pinned Sigstore `cosign` release version.                                                      |

## Operations

### Clearing a Quarantined Release

When a release fails convergence, its tag is written to `/var/lib/homelab-compose/quarantined-release` and skipped until a newer release is published upstream. To retry the same tag after resolving a transient host issue:

```bash
sudo rm -f /var/lib/homelab-compose/quarantined-release
sudo systemctl start homelab-compose-reconcile.service
```

### Rotating the Cosign Signing Key

1. Set `docker_compose_service_cosign_next_public_key` to the new public key PEM and converge all hosts (installs `/etc/containers/cosign-next.pub`).
2. Rotate `COSIGN_PRIVATE_KEY` and `public_key/cosign.pub` in `busybeaver/homelab-services` and cut a new signed release.
3. Replace `configuration/roles/docker_compose_service/files/cosign.pub` with the new public key, clear `docker_compose_service_cosign_next_public_key`, and converge all hosts.
