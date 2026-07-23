# terraform locals file

# in terraform locals are very similar to variables in that they hold values, but generated at runtime.
# with this in mind, locals can leverage the values that come from variables, data sources, or newly deployed resources
# and using that data, allows you to create custom references specific to that deployment without hardcoding values.

locals {
  az_resourcegroup_name = "rg${var.project_name}2026"
  az_static_webapp_name = "wa${var.project_name}2026"

  site_fqdn = "${var.cloudflare_subdomain_name}.${var.cloudflare_root_domain_name}"

  default_tags = {
    application = var.project_name
    environment = var.environment
    managed-by = "terraform"
    repository = "github.com/pasta-up/resume-as-code"
  }

  tags = merge(
    local.default_tags,
    var.az_additional_tags
  )
}