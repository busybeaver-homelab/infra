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
			"cloudflare_api_token": "ci-dummy-token",
			"cloudflare_zone_id":   "ci-dummy-zone-id",
		},
		EnvVars: map[string]string{
			"TOFU_STATE_PASSPHRASE": "ci-dummy-passphrase-for-validation-only",
		},
		NoColor: true,
	}

	terraform.RunTerraformCommand(t, opts, "init", "-backend=false", "-no-color")
	terraform.Validate(t, opts)
	assert.NotNil(t, opts)
}
