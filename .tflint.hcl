config {
  format = "compact"
  call_module_type = "all"
  force  = false
}

# 1. Google Cloud Platform (GCP) Ruleset
plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Enforce standard practices
rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

# 3. Amazon Web Services (AWS) Ruleset
plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# 4. Oracle Cloud Infrastructure (OCI) Ruleset
# NOTE: No official tflint-ruleset-oci exists as of 2026-06-07.
# Track upstream: https://github.com/terraform-linters/tflint/issues
# When an OCI plugin becomes available, add it here following the same pattern.
