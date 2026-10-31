# valetudo_robot

Ansible role that rebuilds a rooted Dreame X40 Ultra vacuum robot with pinned [Valetudo](https://github.com/Hypfer/Valetudo) and Tailscale releases. The robot runs a BusyBox userland without Python, so the role works with `ansible.builtin.raw` on the robot and with controller-side helper scripts for byte transfers.

## Phases

Each phase is a task file imported by `tasks/main.yml` with its own tag:

| Tag                   | Task file       | What it does                                                                                                                                                                                   |
| --------------------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `preflight`, `always` | `preflight.yml` | Sets the `valetudo_robot_transport_env` fact for controller-side tasks and checks that `uname -m` equals `valetudo_robot_expected_arch`.                                                       |
| `backup`              | `backup.yml`    | Captures the factory calibration and identity data once into the git-crypt protected `backups/` tree, writes a `.sha256` sidecar and records the checksum on the robot.                        |
| `install`             | `install.yml`   | Downloads and verifies the pinned Valetudo and Tailscale artifacts on the controller, pushes only binaries that differ from their pin, installs them and maintains the managed postboot block. |

### Install

Check mode: controller cache work and the read-only robot probe still run; every robot change is skipped and a `would push and install` message is reported.

1. Every version and SHA-256 pin is asserted before any download (`R2-GOV-05`): non-empty versions, 64 lowercase hex checksums.
2. `get_url` downloads both artifacts into `valetudo_robot_cache_dir` and verifies the checksums. On every run, only `tailscale` and `tailscaled` are extracted from the verified tarball into a fresh directory keyed by the tarball checksum, and the install checksums are taken from that extraction.
3. The robot's installed checksums are read first. A binary equal to its pin is neither pushed nor installed, so a re-run uploads nothing and never reboots.
4. `check-space` (sum of the binaries to push plus 10 %), `robot-transport.sh push` into `/data/.incoming/`, then `robot-provision.sh install`.
5. The managed block (`templates/root_postboot.managed.sh.j2`) is staged and applied with `robot-provision.sh postboot`. It only starts `tailscaled` behind an `[ -x ]` guard; the vendor template is assumed to start Valetudo.
6. Any `CHANGED=1` notifies `Reboot robot`: with `valetudo_robot_reboot_enabled` the robot reboots and the controller waits for TCP 22, then TCP 80 (300 s each); otherwise a message asks for a manual reboot.

`valetudo_robot_tailscale_enabled` controls only the tailnet join (tailscale phase); the install phase always ships the Tailscale binaries and the guarded managed block.

Reachability and the host-key check run earlier, in the playbook, through `robot-transport.sh probe`.

### Calibration backup

1. `robot-provision.sh backup-status` reads the checksum recorded on the robot (`NONE` if no capture was recorded).
2. A capture runs only if the result is `NONE`, or no `*.sha256` sidecar in `valetudo_robot_backup_dir` holds that checksum.
3. Before any byte is written, `assert-git-crypt-target.sh` checks that the target is git-crypt protected in an unlocked checkout.
4. `robot-transport.sh pull-calibration` streams the archive to `<label>-<YYYYMMDDTHHMMSSZ>.tar` (UTC). The role then writes `<archive>.sha256` in `sha256sum` format and runs `robot-provision.sh mark-backup <sha256>` on the robot.

The phase reports `changed` only when a capture happened. The playbook never commits the archive.

## Helper scripts (`files/`)

| Script                       | Runs on    | Purpose                                                                                             |
| ---------------------------- | ---------- | --------------------------------------------------------------------------------------------------- |
| `robot-provision.sh`         | robot      | Piped through `raw` as a heredoc (`sh -s -- <command>`): space checks, installs, postboot, markers. |
| `robot-transport.sh`         | controller | `probe`, `push` and `pull-calibration` over SSH (or `docker exec` for Molecule).                    |
| `assert-git-crypt-target.sh` | controller | Refuses a calibration target that is not git-crypt protected.                                       |

## Role Variables

| Variable                           | Default                                                     | Description                                                                  |
| ---------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `valetudo_robot_valetudo_version`  | pinned (Renovate: `Hypfer/Valetudo`)                        | Valetudo release tag; the `valetudo-aarch64` asset is installed.             |
| `valetudo_robot_valetudo_sha256`   | pinned                                                      | SHA-256 of `valetudo-aarch64` for the pinned release.                        |
| `valetudo_robot_tailscale_version` | pinned (Renovate: `tailscale/tailscale`)                    | Tailscale stable version without the leading `v`.                            |
| `valetudo_robot_tailscale_sha256`  | pinned                                                      | SHA-256 of `tailscale_<version>_arm64.tgz` from `pkgs.tailscale.com/stable`. |
| `valetudo_robot_valetudo_url`      | upstream release URL template                               | Download URL of `valetudo-aarch64` (Molecule uses a `file://` URL).          |
| `valetudo_robot_tailscale_url`     | `pkgs.tailscale.com/stable` URL template                    | Download URL of the Tailscale arm64 tarball (Molecule uses a `file://` URL). |
| `valetudo_robot_cache_dir`         | `{{ playbook_dir }}/../../.cache/valetudo_robot`            | Controller cache for verified downloads and the rendered postboot block.     |
| `valetudo_robot_expected_arch`     | `aarch64`                                                   | Architecture `uname -m` must report.                                         |
| `valetudo_robot_transport`         | `ssh`                                                       | `ssh`, or `docker` for Molecule only.                                        |
| `valetudo_robot_container`         | `""`                                                        | Container name for the `docker` transport.                                   |
| `valetudo_robot_known_hosts`       | `{{ playbook_dir }}/../../.cache/ansible/robot_known_hosts` | Dedicated, gitignored known-hosts file for the robot.                        |
| `valetudo_robot_backup_repo_root`  | `{{ playbook_dir }}/../..`                                  | Repository root checked by the git-crypt guard.                              |
| `valetudo_robot_backup_dir`        | `{{ playbook_dir }}/../../backups/robots/x40-ultra`         | Directory for calibration archives and sidecars (inside the repository).     |
| `valetudo_robot_backup_label`      | `x40-ultra`                                                 | Archive file name prefix.                                                    |
| `valetudo_robot_reboot_enabled`    | `true`                                                      | Allow reboots after installing binaries or the postboot hook.                |
| `valetudo_robot_tailscale_enabled` | `true`                                                      | Controls only the tailnet join; install always ships the Tailscale binaries. |
| `valetudo_robot_tailscale_tag`     | `tag:type-iot`                                              | Tailscale tag the robot advertises.                                          |
| `valetudo_robot_api_base_url`      | none (set by the playbook)                                  | Valetudo REST API base URL from SOPS-loaded values.                          |
| `valetudo_robot_settings`          | `[]`                                                        | Valetudo settings applied by the configure phase.                            |

Pin updates arrive as Renovate PRs with automerge disabled: update the matching `*_sha256` value in `defaults/main.yml` in the same PR.

## Security

- Robot addresses come only from the SOPS-loaded inventory. Tasks that pass them to the transport helper use `no_log: true` and report failures with sanitized messages.
- Calibration archives are written only after the git-crypt guard passes, with mode `0600`.

## Testing

`molecule/default` uses a BusyBox container (no Python) as the robot, the `docker` transport of `robot-transport.sh` and synthetic `file://` artifacts. `prepare.yml` also builds a throwaway repository with synthetic git-crypt markers for the calibration backup. Run it with `mise run test:ansible:robot`; the idempotence step proves that a second converge changes nothing.
