config {
  format = "compact"
  module = true
  force  = false
}

# 1. Google Cloud Platform (GCP) Ruleset
plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# 2. Cloudflare Ruleset
plugin "cloudflare" {
  enabled = true
  version = "0.9.0"
  source  = "github.com/terraform-linters/tflint-ruleset-cloudflare"
}

# 3. AWS Ruleset
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# 4. OCI (Oracle Cloud Infrastructure) Ruleset
plugin "oci" {
  enabled = true
  version = "0.2.0"
  source  = "github.com/terraform-linters/tflint-ruleset-oci"
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

rule "terraform_sensitive_variable_no_default" {
  enabled = true
}
