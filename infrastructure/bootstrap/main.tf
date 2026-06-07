resource "google_storage_bucket" "state_bucket" {
  name     = var.state_bucket_name
  location = var.gcp_region
  project  = var.gcp_project_id

  # Prevent accidental destruction of the state bucket
  force_destroy = false

  # Enforce high security standards
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  # Keep state history to allow recovery from accidental state corruption
  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
  }
}
