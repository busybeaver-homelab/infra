package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestCloudflareModuleValidates runs `tofu init` and `tofu validate` against the
// Cloudflare root module. Does NOT apply real infrastructure.
func TestCloudflareModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../cloudflare",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"cloudflare_api_token":         "ci-dummy-token",
			"cloudflare_zone_id":           "ci-dummy-zone-id",
			"state_encryption_passphrase":  "ci-dummy-passphrase-for-validation-only",
		},
		// EnvVars ensures the passphrase is available during `tofu init` where
		// the encryption block is evaluated as a static value (TF_VAR_* form).
		EnvVars: map[string]string{
			"TF_VAR_state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
		},
		NoColor: true,
	}

	terraform.RunTerraformCommand(t, opts, "init", "-backend=false", "-no-color")
	terraform.Validate(t, opts)
	assert.NotNil(t, opts)
}
