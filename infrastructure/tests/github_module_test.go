package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestGitHubModuleValidates runs `tofu init` and `tofu validate` against the GitHub
// root module. It does NOT apply or destroy any real infrastructure.
func TestGitHubModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../github",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"github_token": "ci-dummy-token",
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
