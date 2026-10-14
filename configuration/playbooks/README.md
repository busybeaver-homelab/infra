# Ansible Playbooks Directory

This directory contains domain-specific playbooks and the master `site.yml` playbook which acts as the entrypoint for all configuration management tasks:

- `site.yml`: Master playbook importing `base.yml`, `common.yml`, `homelab.yml`, `unifi.yml`, and `cloud.yml`.
- `cloud.yml`: Unified configuration playbook for cloud instances (`oci` and `gcp` groups, children of the `cloud` group).
- `oci.yml`: Thin entrypoint targeting `oci` instances via `cloud.yml`.
- `gcp.yml`: Thin entrypoint targeting `gcp` instances via `cloud.yml`.
