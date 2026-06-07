# OCI Compute Instance — placeholder resource.
# All identifying values (OCIDs, IPs, subnets) are provided via sensitive variables.
resource "oci_core_instance" "main" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "homelab-oci-instance"
  shape               = var.instance_shape

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = var.instance_image_ocid
  }

  metadata = {
    # SSH authorized keys injected via SOPS-encrypted variable — never hardcoded here.
    ssh_authorized_keys = ""
  }
}
