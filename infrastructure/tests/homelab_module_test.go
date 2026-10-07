package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestHomelabModuleValidates runs `tofu init` and `tofu validate` against the Homelab
// root module. It does NOT apply or destroy any real infrastructure.
func TestHomelabModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../homelab",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"proxmox_api_endpoint": "https://proxmox.ci.internal:8006",
			"proxmox_api_token":    "ci@pam!token=dummy",
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

// TestHomelabModuleValidatesWithInsecureFlags tests homelab validation with explicit insecure settings.
func TestHomelabModuleValidatesWithInsecureFlags(t *testing.T) {
	t.Parallel()

	for _, insecure := range []bool{false, true} {
		opts := &terraform.Options{
			TerraformDir:    "../homelab",
			TerraformBinary: "tofu",
			Vars: map[string]interface{}{
				"proxmox_api_endpoint": "https://proxmox.ci.internal:8006",
				"proxmox_api_token":    "ci@pam!token=dummy",
				"proxmox_insecure":     insecure,
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
