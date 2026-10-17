# Security Policy

## Reporting a Vulnerability

Do **not** open a public GitHub issue or pull request for security vulnerabilities, exposed credentials, or privacy leaks.

Please report vulnerabilities privately through [GitHub Security Advisories](https://github.com/busybeaver-homelab/infra/security/advisories/new) (`Security` -> `Report a vulnerability`).

Include in your report:

- Affected file path(s), workflow(s), or module(s)
- Reproduction steps or proof of concept (redacting any sensitive values)
- Potential impact assessment

## Supported Scope

Security fixes are applied only to the `main` branch (`HEAD`):

| Branch / Target                     | Supported |
| :---------------------------------- | :-------- |
| `main`                              | Yes       |
| Feature branches / archived commits | No        |

### In Scope

- Plaintext secret, credential, private key, or PII exposure in commit history, workflows, or OpenTofu/Ansible code
- SOPS or `git-crypt` encryption bypasses in pre-commit or CI guard scripts
- GitHub Actions workflow injection, untrusted trigger privilege escalation, or unpinned third-party actions
- Cloud IAM, firewall/NSG, or Tailscale ACL privilege escalation in OpenTofu modules or Ansible roles

### Out of Scope

- RFC 2606 / RFC 5737 / RFC 3849 synthetic test fixtures and dummy CI credentials in `secrets/credentials.ci.sops.yaml` (verified disjoint from production secrets by `scripts/check-sops-secret-leaks.sh --check-disjointness`)

## Response Expectations

- **Initial acknowledgement:** within 72 hours
- **Triage & remediation plan:** within 7 days
- **Credential rotation (if applicable):** immediate upon verification
