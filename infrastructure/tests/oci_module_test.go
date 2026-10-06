package test

import (
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
