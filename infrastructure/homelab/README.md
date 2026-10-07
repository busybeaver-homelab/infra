# Proxmox Homelab Infrastructure

Declarative OpenTofu module managing Proxmox VE resources.

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

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.60 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_proxmox_api_endpoint"></a> [proxmox\_api\_endpoint](#input\_proxmox\_api\_endpoint) | The HTTPS API endpoint of the Proxmox VE server. | `string` | n/a | yes |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | The Proxmox API token (username@realm!tokenid=secret). | `string` | n/a | yes |
| <a name="input_proxmox_insecure"></a> [proxmox\_insecure](#input\_proxmox\_insecure) | Whether to bypass TLS certificate verification when connecting to the Proxmox VE API. Must default to false. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_proxmox_endpoint"></a> [proxmox\_endpoint](#output\_proxmox\_endpoint) | The configured Proxmox VE API endpoint. |
<!-- END_TF_DOCS -->
