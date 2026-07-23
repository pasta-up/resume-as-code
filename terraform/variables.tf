# terraform variables file

# in terraform, variables are static values statically defined at the time of execution.

variable "project_name" {
  description = "used as a prefix for naming resources in azure, and in tags"
  type        = string
  default     = "resume-as-code"

  validation {
    condition = (
      length(var.project_name) >= 3 &&
      length(var.project_name) <= 40
    )

    error_message = "project_name must be between 3 and 40 characters."
  }
}

variable "environment" {
  description = "deployment environment name"
  type        = string
  default     = "production"

  validation {
    condition = contains(
      ["development", "staging", "production"],
      var.environment
    )

    error_message = "environment must be development, staging, or production"
  }
}

variable "az_location" {
  description = "desired azure region used to deploy resources"
  type        = string
  default     = "centralus"
}


variable "cloudflare_root_domain_name" {
  description = ""
  type        = string
  default     = ""
}

variable "cloudflare_subdomain_name" {
  description = ""
  type        = string
  default     = ""
}

variable "cloudflare_root_domain_zoneid" {
  description = ""
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = ""
  type        = string
  default     = ""
}

variable "cloudflare_proxy_enabled" {
  description = ""
  type        = bool
  default     = ""
}

variable "az_additional_tags" {
  description = ""
  type        = map(string)
  default     = {}
}