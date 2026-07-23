output "resource_group_name" {
  description = "name of the azure resource group"
  value       = azurerm_resource_group.rg.name
}
output "static_web_app_name" {
  description = "name of the azure static web app"
  value       = azurerm_static_web_app.wa.name
}
output "static_web_app_id" {
  description = "resource id of the azure static web app"
  value       = azurerm_static_web_app.wa.id
}
output "az_default_fqdn" {
  description = "default azure-provided hostname for web app"
  value       = azurerm_static_web_app.wa.default_host_name
}
output "custom_fqdn" {
  description = "custom hostname configured for my use"
  value       = local.site_fqdn
}
output "site_url" {
  description = "public url of the resume site"
  value       = "https://${local.site_fqdn}"
}
output "deployment-token" {
  description = "deployment token used by github deployment action(s)"
  value       = azurerm_static_web_app.wa.api_key
  sensitive   = true
}
