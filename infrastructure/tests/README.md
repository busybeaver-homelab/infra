# Infrastructure Tests

Terratest Go tests have been deprecated and replaced by native OpenTofu test suites (`tests/*.tftest.hcl`) located within each infrastructure module:

- `infrastructure/oci/tests/`
- `infrastructure/cloudflare/tests/`
- `infrastructure/gcp/tests/`
- `infrastructure/azure/tests/`
- `infrastructure/github/tests/`
- `infrastructure/homelab/tests/`
- `infrastructure/monitoring/tests/`

To run all infrastructure tests locally:

```bash
mise run test:infra
```
