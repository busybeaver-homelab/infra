check "enforce_always_free_shape_compliance" {
  assert {
    condition     = oci_core_instance.ampere.shape_config[0].ocpus <= 4
    error_message = "Ampere OCPUs must strictly comply with Always Free limits (<= 4 OCPUs)"
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].memory_in_gbs <= 24
    error_message = "Ampere Memory must strictly comply with Always Free limits (<= 24 GB)"
  }
}

check "enforce_mandatory_project_tag" {
  assert {
    condition     = oci_core_instance.ampere.freeform_tags["project"] == "homelab"
    error_message = "Project tag 'homelab' is mandatory on all infrastructure resources"
  }
}
