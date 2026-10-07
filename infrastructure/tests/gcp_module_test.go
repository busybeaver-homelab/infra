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
			"gcp_project_id": "ci-dummy-project",
			"gcp_region":     "us-central1",
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

// TestGCPModuleValidatesWithAlwaysFreeRegions tests all Always Free eligible regions.
func TestGCPModuleValidatesWithAlwaysFreeRegions(t *testing.T) {
	t.Parallel()

	for _, region := range []string{"us-central1", "us-east1", "us-west1"} {
		opts := &terraform.Options{
			TerraformDir:    "../gcp",
			TerraformBinary: "tofu",
			Vars: map[string]interface{}{
				"gcp_project_id": "ci-dummy-project",
				"gcp_region":     region,
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
}

