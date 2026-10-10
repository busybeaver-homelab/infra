check "enforce_network_security_posture" {
  assert {
    condition     = google_compute_network.default_vpc.auto_create_subnetworks == false
    error_message = "VPC must not auto-create subnetworks; custom subnetting required for security"
  }
}

check "enforce_mandatory_project_label" {
  assert {
    condition     = lookup(var.default_labels, "project", "") == "homelab"
    error_message = "Project label 'homelab' is mandatory on all GCP infrastructure"
  }
}
