package test

import (
	"os"
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
			"cloudflare_api_token":  "ci-dummy-token",
			"cloudflare_zone_id":    "ci-dummy-zone-id",
			"cloudflare_account_id": "ci-dummy-account-id",
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

// TestCloudflareModuleR2BucketStructure verifies that the Cloudflare module configures
// the OpenTofu state R2 bucket with expected name and European location hint.
func TestCloudflareModuleR2BucketStructure(t *testing.T) {
	t.Parallel()

	mainContent, err := os.ReadFile("../cloudflare/main.tf")
	assert.NoError(t, err)

	contentStr := string(mainContent)
	assert.Contains(t, contentStr, "resource \"cloudflare_r2_bucket\" \"tfstate\"")
	assert.Contains(t, contentStr, "name       = \"homelab-infra-tfstate\"")
	assert.Contains(t, contentStr, "location   = \"WEUR\"")
}

