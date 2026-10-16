check "enforce_always_free_shape_compliance" {
  assert {
    condition     = oci_core_instance.ampere.shape_config[0].ocpus <= 2
    error_message = "Ampere OCPUs must strictly comply with Always Free limits (<= 2 OCPUs)"
  }

  assert {
    condition     = oci_core_instance.ampere.shape_config[0].memory_in_gbs <= 12
    error_message = "Ampere Memory must strictly comply with Always Free limits (<= 12 GB)"
  }

  assert {
    condition     = sum([for inst in oci_core_instance.amd : inst.source_details[0].boot_volume_size_in_gbs]) + oci_core_instance.ampere.source_details[0].boot_volume_size_in_gbs <= 200
    error_message = "Combined OCI boot volume storage across all instances must not exceed 200 GB Always Free limit"
  }
}

check "enforce_mandatory_project_tag" {
  assert {
    condition     = oci_core_instance.ampere.freeform_tags["project"] == "homelab"
    error_message = "Project tag 'homelab' is mandatory on all infrastructure resources"
  }
}
