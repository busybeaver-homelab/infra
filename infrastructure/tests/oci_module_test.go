package test

import (
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestOCIModuleValidates runs `tofu init` and `tofu validate` against the OCI
// root module. It does NOT apply or destroy any real infrastructure.
func TestOCIModuleValidates(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../oci",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"tenancy_ocid":                "ocid1.tenancy.oc1..dummy",
			"user_ocid":                   "ocid1.user.oc1..dummy",
			"fingerprint":                 "ci-dummy-fingerprint",
			"private_key":                 "ci-dummy-private-key",
			"region":                      "eu-frankfurt-1",
			"compartment_ocid":            "ocid1.compartment.oc1..dummy",
			"state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
		},
		EnvVars: map[string]string{
			"TF_VAR_state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
		},
		NoColor: true,
	}

	terraform.RunTerraformCommand(t, opts, "init", "-backend=false", "-no-color")
	terraform.Validate(t, opts)
	assert.NotNil(t, opts)
}

// TestOCIModuleValidatesWithCustomTailscaleTags verifies that the OCI module accepts
// and validates custom tailscale_common_tags and tailscale_extra_tags_oci variables.
func TestOCIModuleValidatesWithCustomTailscaleTags(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../oci",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"tenancy_ocid":                "ocid1.tenancy.oc1..dummy",
			"user_ocid":                   "ocid1.user.oc1..dummy",
			"fingerprint":                 "ci-dummy-fingerprint",
			"private_key":                 "ci-dummy-private-key",
			"region":                      "eu-frankfurt-1",
			"compartment_ocid":            "ocid1.compartment.oc1..dummy",
			"state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
			"tailscale_common_tags":       []string{"tag:type-server", "tag:os-linux", "tag:hosting-cloud"},
			"tailscale_extra_tags_oci":    []string{"tag:location-ger", "tag:env-oci"},
		},
		EnvVars: map[string]string{
			"TF_VAR_state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
		},
		NoColor: true,
	}

	terraform.RunTerraformCommand(t, opts, "init", "-backend=false", "-no-color")
	terraform.Validate(t, opts)
	assert.NotNil(t, opts)
}

// TestOCICloudInitTemplateStructure verifies that cloud-init.yaml contains the required
// Tailscale bootstrap command structure and the --advertise-tags parameter.
func TestOCICloudInitTemplateStructure(t *testing.T) {
	t.Parallel()

	content, err := os.ReadFile("../oci/cloud-init.yaml")
	assert.NoError(t, err)

	cloudInitStr := string(content)
	assert.Contains(t, cloudInitStr, "--advertise-tags=\"${tailscale_tags}\"")
	assert.Contains(t, cloudInitStr, "--authkey=\"${tailscale_auth_key}\"")
	assert.Contains(t, cloudInitStr, "--hostname=\"${hostname}\"")
}

// TestOCIModuleValidatesWithCustomDefaultTags verifies that the OCI module accepts
// and validates a custom default_freeform_tags map variable.
func TestOCIModuleValidatesWithCustomDefaultTags(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir:    "../oci",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"tenancy_ocid":                "ocid1.tenancy.oc1..dummy",
			"user_ocid":                   "ocid1.user.oc1..dummy",
			"fingerprint":                 "ci-dummy-fingerprint",
			"private_key":                 "ci-dummy-private-key",
			"region":                      "eu-frankfurt-1",
			"compartment_ocid":            "ocid1.compartment.oc1..dummy",
			"state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
			"default_freeform_tags": map[string]string{
				"project": "custom-homelab",
				"env":     "ci",
			},
		},
		EnvVars: map[string]string{
			"TF_VAR_state_encryption_passphrase": "ci-dummy-passphrase-for-validation-only",
		},
		NoColor: true,
	}

	terraform.RunTerraformCommand(t, opts, "init", "-backend=false", "-no-color")
	terraform.Validate(t, opts)
	assert.NotNil(t, opts)
}
