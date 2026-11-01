# Ansible Playbooks Directory

This directory contains domain-specific playbooks and the master `site.yml` playbook which acts as the entrypoint for all configuration management tasks:

- `site.yml`: Master playbook importing `base.yml`, `common.yml`, `homelab.yml`, `unifi.yml`, and `cloud.yml`.
- `cloud.yml`: Unified configuration playbook for cloud instances (`oci` and `gcp` groups, children of the `cloud` group).
- `oci.yml`: Thin entrypoint targeting `oci` instances via `cloud.yml`.
- `gcp.yml`: Thin entrypoint targeting `gcp` instances via `cloud.yml`.
- `robots.yml`: Operator-run rebuild of the rooted Dreame X40 Ultra (`valetudo_robot` role). It is **not** imported by `site.yml`; a real run needs per-action owner confirmation.
  - Play 1 (controller): early asserts that the SOPS file is canonical and matches the mode (`is_ci_environment` only with `credentials.ci.sops.yaml`, `is_production` only with `credentials.sops.yaml`, checked before decryption), SOPS load and environment sentinel, fail-closed checks for missing `valetudo_robot` keys and for placeholder values (placeholder check skipped in CI mode unless `-e valetudo_robot_force_placeholder_check=true`), a sweep of stale `robot_key.*` files in `.cache/ansible`, the SSH key written to a 0600 tempfile, TCP 22 checks on `lan_host` then `ap_host` (`-e valetudo_robot_probe_timeout=<seconds>`, default 5), the `CI mode never contacts a robot` guard, `robot-transport.sh probe`, and `add_host` into `robots`.
  - Play 2 (`robots`): runs the role; its `always` section deletes the key tempfile when a role task fails.
  - Play 3 (controller): deletes the key tempfile after the robot play, which covers the wifi phase ending the host (`meta: end_host`). Unreachable or all-hosts-failed runs abort before Play 3; the key (0600, gitignored) then stays until the next run's stale sweep removes it.
