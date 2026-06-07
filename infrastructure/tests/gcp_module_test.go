package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestGCPModuleValidates runs `tofu init` and `tofu validate` against the GCP
// root module. It does NOT apply or destroy any real infrastructure.
// Full apply/destroy tests require OIDC credentials and are not run in CI on forks.
func TestGCPModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../gcp",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"gcp_project_id":              "ci-dummy-project",
			"gcp_region":                  "us-central1",
			"state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
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
