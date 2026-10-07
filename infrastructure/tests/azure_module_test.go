package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestAzureModuleValidates runs `tofu init` and `tofu validate` against the Azure
// root module. It does NOT apply or destroy any real infrastructure.
func TestAzureModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../azure",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"azure_subscription_id": "ci-dummy-subscription-id",
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
