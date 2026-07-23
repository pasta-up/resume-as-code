# terraform main resource file

# in my example, I am loading all the resources  from this file, but in more complex deployments, you may break your
# resources out into separate files just like the other components.

# Azure Resources
# ===============================================================================
resource "azurerm_resource_group" "rg" {
  name     = local.az_resourcegroup_name
  location = var.az_location
  tags     = local.tags
}

resource "azurerm_static_web_app" "wa" {
  name                = local.az_static_webapp_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku_tier = "Free"
  sku_size = "Free"
}

resource "azurerm_static_web_app_custom_domain" "fqdn" {
  static_web_app_id = azurerm_static_web_app.wa.id
  domain_name       = local.site_fqdn
  validation_type   = "cname-delegation"

  depends_on = [
    time_sleep.wait_for_dns
  ]
}

# Cloudflare Resources
# ===============================================================================
resource "cloudflare_dns_record" "fqdn" {
  zone_id = var.cloudflare_root_domain_zoneid

  name    = local.site_fqdn
  type    = "CNAME"
  content = azurerm_static_web_app.wa.default_host_name
  ttl     = 1
  proxied = var.cloudflare_proxy_enabled
}

# Utility Resources
# ===============================================================================
resource "time_sleep" "wait_for_dns" {
  depends_on = [
    cloudflare_dns_record.fqdn
  ]

  create_duration = "300s"
}
