# 🏡 Homelab & Cloud Infrastructure GitOps

Welcome to the GitOps repository for managing Cloud (GCP, Cloudflare) and Homelab (Ubuntu Server, UniFi) infrastructure. This repository uses **OpenTofu** for infrastructure provisioning, **Ansible** for system configuration, **SOPS** with **age** for secrets management, and **Lefthook** to enforce quality and security guardrails.

---

## 🗺️ High-Level Architecture

The following diagram illustrates how the infrastructure and configuration components relate:

```mermaid
graph TD
    subgraph Control ["💻 Control Node (Admin/CI)"]
        Mise["🛠️ Mise (Tool Manager)"]
        Tofu["☁️ OpenTofu"]
        Ans["🏎️ Ansible"]
        SOPS["🔑 SOPS / Age"]
    end

    subgraph Cloud ["☁️ Cloud Services"]
        CF["⚡ Cloudflare (DNS/WAF & R2 State Bucket)"]
        OCI["⭕ Oracle Cloud Infrastructure (Always Free)"]
        GCP["🌐 Google Cloud Platform (Always Free)"]
        Azure["🔷 Microsoft Azure"]
    end

    subgraph Homelab ["🏠 Homelab"]
        UniFi["📡 UniFi Network"]
        Ubuntu["🐧 Ubuntu Servers (Proxmox / Metal)"]
    end

    %% Provisioning flow
    Tofu -.->|"Encrypted State (AES-GCM)"| CF
    Tofu ===>|Provisions| OCI
    Tofu ===>|Provisions| GCP
    Tofu ===>|Provisions| Azure
    Tofu ===>|Manages| CF

    %% Configuration flow
    Ans ===>|Configures OS/Services| Ubuntu
    Ans ===>|Configures Cloud VM| OCI
    Ans ===>|Manages API| UniFi

    %% Tool links
    Mise --> Tofu
    Mise --> Ans
    Mise --> SOPS
```

---

## 🛠️ Global Toolset

This repository pins tools globally in `.mise.toml` to ensure every administrator and CI agent runs the identical binary versions:

| Tool               | Version | Purpose                                                       |
| :----------------- | :------ | :------------------------------------------------------------ |
| **OpenTofu**       | `1.13`  | Declarative cloud and local resource provisioning             |
| **TFLint**         | `0.64`  | OpenTofu/Terraform linter for cloud best practices and errors |
| **Ansible**        | `14`    | Idempotent software installation and configuration management |
| **SOPS**           | `3.13`  | File-level encryption/decryption of secrets                   |
| **Age**            | `1.3`   | Modern and secure file-level encryption and key generation    |
| **Lefthook**       | `2.1`   | Parallel pre-commit Git hooks for security and quality        |
| **Python**         | `3.14`  | Root runtime for Ansible and infrastructure scripting         |
| **Ruff**           | `0.16`  | Lightning-fast Python linter and code formatter               |
| **ShellCheck**     | `0.11`  | Bash/shell script static analyzer and linter                  |
| **Terraform-Docs** | `0.24`  | Automated markdown documentation for OpenTofu modules         |
| **TruffleHog**     | `3`     | High-entropy secrets and credential scanning in Git commits   |
| **Bats**           | `1.14`  | Bash automated testing framework for unit and CI verification |
| **Oxlint**         | `1.84`  | High-performance linter for repository web and app assets     |
| **Oxfmt**          | `0.71`  | Fast formatter wrapper for markdown, JSON, and web assets     |
| **Shfmt**          | `3.14`  | Shell script code formatter enforcing consistent shell styles |
| **Yq**             | `4`     | YAML and JSON command-line processor                          |
| **Node**           | `lts`   | JavaScript runtime for repository linters and tooling         |
| **Go**             | `1.27`  | Systems runtime for developer and testing utilities           |
| **Act**            | `0.2`   | Local execution of GitHub Actions workflows                   |
| **Git-Crypt**      | `0.7+`  | Transparent file-level encryption for sensitive docs/ tree    |

---

## 📋 Prerequisites

Before setting up the repository, ensure your control machine has the following dependencies:

1. **Operating System:** macOS (Apple Silicon or Intel) or Linux (Ubuntu, Debian, Fedora, Arch)
2. **Git:** `git` version `2.34+`
3. **Git-Crypt:** Required to view and edit encrypted documentation and backup artifacts under `docs/` and `backups/`.
   - Installation (macOS): `brew install git-crypt`
   - Installation (Linux/Debian): `sudo apt-get install git-crypt`
4. **Mise-cli:** Recommended for automated version management.
   - Installation (macOS): `brew install mise`
   - Installation (Linux): `curl https://mise.run | sh`

---

## 🚀 Quickstart

Get your local workspace up and running in under two minutes:

### Step 1: Clone and Run the Bootstrap Script

Run the automated bootstrap script to install Mise (if missing), run `mise install` to provision global tools, unlock encrypted documentation and backups (`docs/`, `backups/`) if your production GPG key is imported, generate a local secret keypair, and set up your Python virtual environment:

```bash
git clone https://github.com/jmollner/homelab-infra.git
cd homelab-infra
./scripts/bootstrap.sh
```

> [!NOTE]
> All designs and plans in `docs/` and backup archives in `backups/` are encrypted at rest using `git-crypt` with the production GPG key (`5EE1590FF82DC2A3829D224FAA73ACF495CC009D`). If `scripts/bootstrap.sh` does not detect your GPG key, import it and run `git-crypt unlock` manually.

### Step 2: Configure Your Shell Integration

Ensure `mise` is integrated with your terminal so the path resolves the pinned tools and automatically activates the Python environment when entering the workspace:

_For Zsh (~/.zshrc):_

```bash
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc
```

_For Bash (~/.bashrc):_

```bash
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
source ~/.bashrc
```

### Step 3: Configure Your SOPS Keys

Make sure your private age key location is set in your environment:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

---

## 📁 Repository Directory Layout

The structure of the repository is modular and structured as follows:

```text
.
├── .github/                 # GitHub Actions workflows and templates
├── apps/                    # Self-hosted applications architecture specifications & compose manifests
├── backups/                 # Offline backups and recovery archives (git-crypt encrypted)
├── configuration/           # Ansible inventories, playbooks, and roles
│   ├── inventories/         # Environment inventories (production, testing)
│   ├── playbooks/           # Ansible master & domain playbooks
│   └── roles/               # Reusable Ansible configuration units (base_ubuntu_server, restic_backup)
├── docs/                    # Architecture, design proposals, plans (git-crypt encrypted)
├── infrastructure/          # OpenTofu root modules with Cloudflare R2 remote state backend
│   ├── azure/               # Microsoft Azure resource groups and credentials
│   ├── cloudflare/          # DNS, tunnels, access rules, and R2 state/backup buckets
│   ├── gcp/                 # GCP compute, networks, and identities (Always Free)
│   ├── github/              # Repository secrets, environments, and CI variables
│   ├── homelab/             # Proxmox VMs, LXC containers, and local networks
│   ├── monitoring/          # Healthchecks.io checks and alerting integration
│   └── oci/                 # Oracle Cloud compute, VCN, budgets, and storage (Always Free)
├── scripts/                 # Administration and git-hook helper scripts
└── secrets/                 # Decoy/CI keys and secrets guides
```
