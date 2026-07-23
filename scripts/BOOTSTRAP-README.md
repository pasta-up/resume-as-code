# resume-as-code
## azure-bootstrap readme
### purpose
terraform can only run if it has a account to authenticate to your cloud provider with.  in addition, in order for terraform to store its state data, and subsequently retain any state information desired from one execution of terraform to the next, it requires some kind of storage for its state.

the azure-bootstrap.ps1 powershell script, creates the prerequsite resources for you, assigns the desired permissions/roles and then outputs the results in your terminal to be added into your terraform configurations.

### execution
the powershell script is parameterized if you want to provide any values at runtime, but since this is generally a one-time execute situation, I prefer leveraging the default values when they are not sensitive.

I think the easiest way to run this is:
1. view the azure-bootstrap.ps1 file, ctrl+a and copy.
2. login to your azure portal (with an account with appropriate access)
3. open your azure cloud shell in powershell mode and run:
    - ``code bootstrap.ps1``
4. in the editor, paste your code, and save (ctrl+s).
5. in the terminal execute via:
    - ``./bootstrap.ps1``

### example output
 - these values have been modified for the example, these are not real values.
```powershell

bootstrap complete
==================

application name:       terraform-backend
azure client id:         c9b8d5d6-2f47-4f9a-a1d8-86e8f94d54d7
azure tenant id:         1e4c79aa-6f14-42e2-b0b8-fd98a0b1a92d
azure subscription id:   54f3d8d1-8e2c-4b74-97b3-2f1f7e45c6ad
service principal id:    b7f0d2c4-91a8-4a5d-bf2e-8e3d6c1a7f55
resource group:          rg-terraform-backend
storage account:         st2026terraformrac123456
state container:         tfstate

terraform backend configuration snippet:

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-backend"
    storage_account_name = "st2026terraformrac123456"
    container_name       = "tfstate"
    key                  = "resume-as-code.tfstate"
    use_azuread_auth     = true
  }
}

recommended GitHub repository variables:

AZURE_CLIENT_ID=c9b8d5d6-2f47-4f9a-a1d8-86e8f94d54d7
AZURE_TENANT_ID=1e4c79aa-6f14-42e2-b0b8-fd98a0b1a92d
AZURE_SUBSCRIPTION_ID=54f3d8d1-8e2c-4b74-97b3-2f1f7e45c6ad
```