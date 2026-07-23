# terraform provider settings file

# in terraform providers are the framework/context for what you can deploy into.
# providers translate the terraform code into api calls to the vendor/solution you are creating resources in.
# for major cloud providers, you will make your selection from the terraform registry (https://registry.terraform.com), 
# but you can build custom providers for in-house solutions as well.

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"

  resource_providers_to_register = [
    "Microsoft.Storage",
    "Microsoft.Web",
  ]
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "time" {}