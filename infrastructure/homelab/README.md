# Proxmox Homelab Infrastructure (Placeholder)

> **Status (`R2-OPS-06`):** Placeholder OpenTofu module with **0 managed resources** (provider, state encryption, and input validations only). Excluded from automated drift detection until Proxmox VE resources are provisioned.

Declarative OpenTofu module scaffolding for future Proxmox VE resources.

## Proxmox TLS Verification & CA Trust Setup

By default, `var.proxmox_insecure` is set to `false` to enforce strict TLS verification when communicating with the Proxmox VE API endpoint (`https://...:8006`).

If using Proxmox VE's self-signed or internal cluster Certificate Authority (CA):

### 1. Retrieve the Proxmox CA Certificate

From the Proxmox VE host, retrieve the cluster CA certificate located at `/etc/pve/pve-root-ca.pem`.

### 2. Install CA on Administrative Workstations / CI Runners

- **Debian / Ubuntu**:

  ```bash
  sudo cp pve-root-ca.pem /usr/local/share/ca-certificates/pve-root-ca.crt
  sudo update-ca-certificates
  ```

- **macOS**:

  ```bash
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain pve-root-ca.pem
  ```

- **OpenTofu / Terraform environment variable**:
  Alternatively, export the custom CA certificate bundle path before running OpenTofu:
  ```bash
  export SSL_CERT_FILE=/path/to/pve-root-ca.pem
  ```

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version   |
| ------------------------------------------------------------------------ | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.13.1 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement_proxmox)       | 0.116.0   |

## Inputs

| Name                                                                                                                 | Description                                                                                                                                        | Type     | Required |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | :------: |
| <a name="input_proxmox_api_endpoint"></a> [proxmox\_api\_endpoint](#input_proxmox_api_endpoint)                      | The HTTPS API endpoint of the Proxmox VE server.                                                                                                   | `string` |   yes    |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input_proxmox_api_token)                               | The Proxmox API token (username@realm!tokenid=secret).                                                                                             | `string` |   yes    |
| <a name="input_proxmox_insecure"></a> [proxmox\_insecure](#input_proxmox_insecure)                                   | Whether to bypass TLS certificate verification when connecting to the Proxmox VE API. Must default to false.                                       | `bool`   |    no    |
| <a name="input_state_encryption_passphrase"></a> [state\_encryption\_passphrase](#input_state_encryption_passphrase) | State and plan encryption passphrase. Source: production SOPS opentofu.state\_encryption\_passphrase. No default, so a missing value fails closed. | `string` |   yes    |

## Outputs

| Name                                                                                 | Description                             |
| ------------------------------------------------------------------------------------ | --------------------------------------- |
| <a name="output_proxmox_endpoint"></a> [proxmox\_endpoint](#output_proxmox_endpoint) | The configured Proxmox VE API endpoint. |

<!-- END_TF_DOCS -->
