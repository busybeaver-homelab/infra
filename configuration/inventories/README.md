# Ansible Inventories Directory

This directory contains inventory configurations for managing both homelab and cloud servers:

- `hosts.yml` — Static base group hierarchy (`cloud` -> `oci`, `gcp`, plus `homelab` and `unifi`) and connection defaults (`ansible_user: ubuntu`, `ansible_port: 22`, SOPS-derived SSH key path).
- `hosts.generated.yml` (gitignored) — Materialized by `scripts/generate-inventory.sh` (`mise run ansible:inventory`), which reads the encrypted OpenTofu `ansible_inventory` outputs from `infrastructure/oci` and `infrastructure/gcp` (or offline `--from-json` / `--input-json` fixtures) and fails closed if zero hosts are discovered (`STD-AN-20`, `STD-AN-29`, `STD-AN-49`).
