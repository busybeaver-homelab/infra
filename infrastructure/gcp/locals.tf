locals {
  default_labels = merge(var.default_labels, {
    project = "homelab"
  })
}
