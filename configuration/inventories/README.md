# Ansible Inventories Directory

This directory contains inventory configurations for managing both homelab and cloud servers:

- `01-Homelab-Static.yml` — Static inventory for on-premises homelab hosts and network equipment (`unifi`).
- `02-Cloud-Dynamic.yml` — Base group hierarchy (`cloud` -> `oci`, `gcp`) populated at runtime by `99-Dynamic-Inventory.ini`.
- `99-Dynamic-Inventory.ini` (gitignored) — Materialized by `scripts/generate-inventory.sh` (`mise run ansible:inventory`), which reads the encrypted OpenTofu `ansible_inventory` outputs from `infrastructure/oci` and `infrastructure/gcp` (with SOPS MagicDNS fallback when `--allow-sops-fallback` is passed).
