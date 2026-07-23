# terraform backend file

# the backend species how terriform will store its state data.  this can vary wildy depending on where you want to store your state.
# without this, everytime terraform runs, it relies on local files to store state, which is not ideal in environments where the machine executing the code
# is dynamically selected, or multiple users regularly run the terraform.

# for my example, since I'm deploying in Azure already, I am using azure to host my state as well.
# these resources are created via the azure-bootstrap.ps1 script.

# also note that additional values are required for backend functionality, and are typically provided here in the backend block, 
# however, as this is a public repo, I am providing some of these values in the github-action at runtime.

terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}