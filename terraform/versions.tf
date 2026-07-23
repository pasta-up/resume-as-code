# terraform version control file

# specifies which range of versions are acceptable for various components, and indicates which providers/versions are required.

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }

    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }
  }
}