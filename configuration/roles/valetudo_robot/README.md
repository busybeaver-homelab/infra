# valetudo_robot

Ansible role that rebuilds a rooted Dreame X40 Ultra vacuum robot with pinned [Valetudo](https://github.com/Hypfer/Valetudo) and Tailscale releases. The robot runs a BusyBox userland without Python, so the role works with `ansible.builtin.raw` on the robot and with controller-side helper scripts for byte transfers.

## Phases

Each phase is a task file imported by `tasks/main.yml` with its own tag:

| Tag                   | Task file       | What it does                                                                                                                                                                                   |
| --------------------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `preflight`, `always` | `preflight.yml` | Sets the `valetudo_robot_transport_env` fact for controller-side tasks and checks that `uname -m` equals `valetudo_robot_expected_arch`.                                                       |
| `backup`              | `backup.yml`    | Captures the factory calibration and identity data once into the git-crypt protected `backups/` tree, writes a `.sha256` sidecar and records the checksum on the robot.                        |
| `install`             | `install.yml`   | Downloads and verifies the pinned Valetudo and Tailscale artifacts on the controller, pushes only binaries that differ from their pin, installs them and maintains the managed postboot block. |
| `wifi`                | `wifi.yml`      | Only when `valetudo_robot_on_lan` is false: PUTs the home Wi-Fi to Valetudo, tells the operator to reconnect and re-run with `--tags configure,tailscale`, then ends the host.                 |
| `configure`           | `configure.yml` | Probes a protected endpoint with the SOPS basic-auth credentials, enables basic auth when needed (one re-probe, no loop) and applies the settings whose `desired` is not a subset.             |
| `tailscale`           | `tailscale.yml` | Only when `valetudo_robot_tailscale_enabled`: joins the tailnet with the single-use OpenTofu auth key unless the robot's Tailscale backend is already `Running`.                               |

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

### Wi-Fi and configure

Both phases call Valetudo's REST API from the controller with `ansible.builtin.uri` (the robot has no Python). The API paths are role defaults (`valetudo_robot_api_*_path`); they are Valetudo's documented v2 paths and must be verified at recon (plan Task 0).

- `wifi`: needs `valetudo_robot_on_lan` (set by the playbook). When it is false the PUT is sent and `meta: end_host` stops the host; when it is true the phase does nothing.
- `configure`: if the probe fails, the auth config is PUT without credentials (retried once with the SOPS credentials if refused) and the endpoint is re-probed once. If it still fails, the play stops with `basic auth could not be set: Valetudo rejects the SOPS credentials and refuses unauthenticated changes; reset auth via SSH per runbook`. Each entry of `valetudo_robot_settings` is read first and PUT only when `desired` is not a subset of the response.
- Check mode: reads and probes run, PUTs are skipped with a `would change` message. A converged robot receives zero PUTs.
- Every task that carries credentials, the PSK or API responses is `no_log: true`; messages never include the base URL.

### Tailscale

1. Asserts `valetudo_robot_tailscale_hostname` (no default, from SOPS) and `valetudo_robot_tailscale_tag`, then reads the robot's Tailscale state read-only. A robot that is already `Running` is left alone: no key fetch, no push, `changed=0`.
2. Otherwise `scripts/get-tofu-robot-vars.sh` (`valetudo_robot_tofu_vars_script`, extra arguments from `valetudo_robot_tofu_vars_args`) runs on the controller with `no_log`, `run_once` and `check_mode: false`, exactly like `cloud.yml` runs `get-tofu-restic-vars.sh`. A failure points at the helper without showing its stderr.
3. The key goes to a `0600` controller tempfile, `robot-transport.sh push` stages it as `/data/.incoming/tskey` and `robot-provision.sh tailscale-join` runs `tailscale up --auth-key=file:...`. The tempfile and any staged key are removed in `always`; the key never appears in argv or output. The backend state is re-read afterwards and must be `Running`.
4. Exit 6 means the key may be expired or already used: refresh it with `tofu apply -replace='tailscale_tailnet_key.robot'` in `infrastructure/mesh` (per-action owner confirmation), then re-run with `--tags tailscale`. If `tailscaled` is not running, reboot the robot so the postboot hook starts it.
5. Check mode: only the state read runs, and `would join tailnet as <tag>` is reported. Messages never include the hostname.

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

| Variable                                           | Default                                                     | Description                                                                  |
| -------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `valetudo_robot_valetudo_version`                  | pinned (Renovate: `Hypfer/Valetudo`)                        | Valetudo release tag; the `valetudo-aarch64` asset is installed.             |
| `valetudo_robot_valetudo_sha256`                   | pinned                                                      | SHA-256 of `valetudo-aarch64` for the pinned release.                        |
| `valetudo_robot_tailscale_version`                 | pinned (Renovate: `tailscale/tailscale`)                    | Tailscale stable version without the leading `v`.                            |
| `valetudo_robot_tailscale_sha256`                  | pinned                                                      | SHA-256 of `tailscale_<version>_arm64.tgz` from `pkgs.tailscale.com/stable`. |
| `valetudo_robot_valetudo_url`                      | upstream release URL template                               | Download URL of `valetudo-aarch64` (Molecule uses a `file://` URL).          |
| `valetudo_robot_tailscale_url`                     | `pkgs.tailscale.com/stable` URL template                    | Download URL of the Tailscale arm64 tarball (Molecule uses a `file://` URL). |
| `valetudo_robot_cache_dir`                         | `{{ playbook_dir }}/../../.cache/valetudo_robot`            | Controller cache for verified downloads and the rendered postboot block.     |
| `valetudo_robot_expected_arch`                     | `aarch64`                                                   | Architecture `uname -m` must report.                                         |
| `valetudo_robot_transport`                         | `ssh`                                                       | `ssh`, or `docker` for Molecule only.                                        |
| `valetudo_robot_container`                         | `""`                                                        | Container name for the `docker` transport.                                   |
| `valetudo_robot_known_hosts`                       | `{{ playbook_dir }}/../../.cache/ansible/robot_known_hosts` | Dedicated, gitignored known-hosts file for the robot.                        |
| `valetudo_robot_backup_repo_root`                  | `{{ playbook_dir }}/../..`                                  | Repository root checked by the git-crypt guard.                              |
| `valetudo_robot_backup_dir`                        | `{{ playbook_dir }}/../../backups/robots/x40-ultra`         | Directory for calibration archives and sidecars (inside the repository).     |
| `valetudo_robot_backup_label`                      | `x40-ultra`                                                 | Archive file name prefix.                                                    |
| `valetudo_robot_reboot_enabled`                    | `true`                                                      | Allow reboots after installing binaries or the postboot hook.                |
| `valetudo_robot_tailscale_enabled`                 | `true`                                                      | Controls only the tailnet join; install always ships the Tailscale binaries. |
| `valetudo_robot_tailscale_tag`                     | `tag:type-iot`                                              | Tailscale tag the robot advertises.                                          |
| `valetudo_robot_tailscale_hostname`                | none (SOPS)                                                 | Tailnet hostname; required while the join is enabled, never printed.         |
| `valetudo_robot_tofu_vars_script`                  | `<repo root>/scripts/get-tofu-robot-vars.sh`                | Controller helper that prints the robot auth key from OpenTofu outputs.      |
| `valetudo_robot_tofu_vars_args`                    | `[]`                                                        | Extra helper arguments (tests pass `--mesh-json <fixture>`).                 |
| `valetudo_robot_api_base_url`                      | none (set by the playbook)                                  | Valetudo REST API base URL from SOPS-loaded values.                          |
| `valetudo_robot_on_lan`                            | none (set by the playbook)                                  | Whether the controller is on the home network; the wifi phase needs it.      |
| `valetudo_robot_basic_auth_username` / `_password` | none (SOPS)                                                 | Valetudo basic-auth credentials; never defaulted.                            |
| `valetudo_robot_wifi_ssid` / `_psk`                | none (SOPS)                                                 | Home Wi-Fi credentials for the wifi phase; never defaulted.                  |
| `valetudo_robot_api_*_path`                        | documented v2 paths                                         | Version, auth config, Wi-Fi and probe paths (verify at recon).               |
| `valetudo_robot_api_timeout`                       | `10`                                                        | Seconds per API request.                                                     |
| `valetudo_robot_settings`                          | `[]`                                                        | Valetudo settings applied by the configure phase.                            |

Pin updates arrive as Renovate PRs with automerge disabled: update the matching `*_sha256` value in `defaults/main.yml` in the same PR.

## Security

- Robot addresses come only from the SOPS-loaded inventory. Tasks that pass them to the transport helper use `no_log: true` and report failures with sanitized messages.
- Calibration archives are written only after the git-crypt guard passes, with mode `0600`.

## Testing

`molecule/default` uses a BusyBox container (no Python) as the robot, the `docker` transport of `robot-transport.sh` and synthetic `file://` artifacts. `prepare.yml` also builds a throwaway repository with synthetic git-crypt markers for the calibration backup. Run it with `mise run test:ansible:robot`; the idempotence step proves that a second converge changes nothing.

A second platform (`valetudo-robot-mock-api`, Python alpine pinned by digest) runs `molecule/default/mock_valetudo.py`, a stdlib-only mock of the Valetudo API that logs every request to `/tmp/requests.jsonl` (Authorization recorded only as present or absent). A second instance started with `--scenario auth_mismatch` backs the fail-closed check. Verify reads the logs to prove one auth PUT and one settings PUT on the first converge, zero afterwards, no retry loop on mismatch, and exactly one Wi-Fi PUT followed by `end_host`.
