<#
.SYNOPSIS
    This script is expected to be run from the Azure Cloud Shell PowerShell
    console within your Azure tenant.

    The actions in this script create and configure the prerequisite resources
    required to use Terraform to deploy Azure resources from a GitHub Actions
    pipeline.

    You must have an active Microsoft Azure tenant with an existing subscription.

.DESCRIPTION
    Creates:
        - Microsoft Entra ID application registration and service principal
        - resource group and storage account used to manage Terraform state
        - private tfstate blob container

    Configures:
        - required Azure role assignments (RBAC) for the service principal
        - optional federated identity support for GitHub Actions
        - using OIDC and passwordless authentication
        - blob versioning for the Terraform state storage account

    Designed to run in Azure Cloud Shell using PowerShell, not Bash.

.NOTES
    The user running this script must have permission to:
        - create app registrations and service principals
        - create resource groups within the desired subscription
        - create storage accounts within the desired resource group
        - create and assign Azure role assignments (RBAC)
#>

param (
    [parameter()]
    [string]$location = "centralus",

    [parameter()]
    [string]$resourcegroupname = "rg-terraform-backend",

    [parameter()]
    [string]$applicationname = "terraform-backend",

    [parameter()]
    [string]$containername = "tfstate",

    [parameter()]
    [string]$githubowner = "pasta-up",

    [parameter()]
    [string]$githubrepo = "resume-as-code",

    [parameter()]
    [string]$githubenv = "primary"
)

$erroractionpreference = "stop"
set-strictmode -version latest

function Invoke-AzureCli {
    param (
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & az @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw @"
Azure CLI command failed:

az $($Arguments -join ' ')
"@
    }
}

function test-stname-availability {
    param (
        [parameter(mandatory)]
        [string]$storageaccountname
    )

    $result = invoke-azurecli -arguments @(
        "storage", "account", "check-name",
        "--name", $storageaccountname,
        "--query", "nameAvailable",
        "--output", "tsv",
        "--only-show-errors"
    )

    return "$result".trim().tolowerinvariant() -eq "true"
}

write-host ""
write-host "terraform azure bootstrap" -foregroundcolor cyan
write-host "=========================" -foregroundcolor cyan
write-host ""

# -----------------------------------------------------------
#    confirm authentication and get subscription metadata
# -----------------------------------------------------------

write-host "reading active subscription..." -foregroundcolor yellow

$accountjson = invoke-azurecli -arguments @(
    "account", "show",
    "--output", "json",
    "--only-show-errors"
)

$account = $accountjson | convertfrom-json

$subscriptionid   = $account.id
$subscriptionname = $account.name
$tenantid         = $account.tenantid

write-host "azure subscription: $subscriptionname"
write-host "azure subscription id: $subscriptionid"
write-host "azure tenant id: $tenantid"
write-host ""

# -----------------------------------------------------------
#    generate globally unique storage account name
#
#    storage account names:
#        - must be globally unique
#        - may contain only lowercase letters and numbers
#        - must be between 3 and 24 characters
#
#    template: st2026terraformrac######
# -----------------------------------------------------------

write-host "generating storage account name..." -foregroundcolor yellow

$storageaccountprefix = "st2026terraformrac"
$storageaccountname   = $null

for ($attempt = 1; $attempt -le 5; $attempt++) {
    $suffix    = get-random -minimum 0 -maximum 1000000
    $candidate = "{0}{1:D6}" -f $storageaccountprefix, $suffix

    if (test-stname-availability -storageaccountname $candidate) {
        $storageaccountname = $candidate
        break
    }
}

if ([string]::isnullorwhitespace($storageaccountname)) {
    throw "unable to generate an available storage account name after 5 attempts."
}

write-host "storage account name: $storageaccountname" -foregroundcolor green
write-host ""

# -----------------------------------------------------------
#             create or retrieve resource group
# -----------------------------------------------------------

write-host "creating or verifying resource group '$resourcegroupname'..." `
    -foregroundcolor yellow

$resourcegroupexists = invoke-azurecli -arguments @(
    "group", "exists",
    "--name", $resourcegroupname,
    "--output", "tsv",
    "--only-show-errors"
)

if ("$resourcegroupexists".trim().tolowerinvariant() -eq "true") {
    write-host "resource group already exists." -foregroundcolor darkyellow
}
else {
    invoke-azurecli -arguments @(
        "group", "create",
        "--name", $resourcegroupname,
        "--location", $location,
        "--tags",
            "managed-by=azure-bootstrap-script",
            "purpose=terraform-backend",
            "project=resume-as-code",
        "--output", "none",
        "--only-show-errors"
    ) | out-null

    write-host "resource group created." -foregroundcolor green
}

$resourcegroupid = invoke-azurecli -arguments @(
    "group", "show",
    "--name", $resourcegroupname,
    "--query", "id",
    "--output", "tsv",
    "--only-show-errors"
)

$resourcegroupid = "$resourcegroupid".trim()

# -----------------------------------------------------------
#        create or retrieve application registration
# -----------------------------------------------------------

write-host ""
write-host "creating Microsoft Entra ID application '$applicationname'..." `
    -foregroundcolor yellow

$existingapplicationjson = invoke-azurecli -arguments @(
    "ad", "app", "list",
    "--display-name", $applicationname,
    "--query", "[0]",
    "--output", "json",
    "--only-show-errors"
)

$existingapplication = $existingapplicationjson | convertfrom-json

if (
    $null -ne $existingapplication -and
    -not [string]::isnullorwhitespace($existingapplication.appid)
) {
    $applicationid       = $existingapplication.appid
    $applicationobjectid = $existingapplication.id

    write-host "application registration already exists." `
        -foregroundcolor darkyellow
}
else {
    $applicationjson = invoke-azurecli -arguments @(
        "ad", "app", "create",
        "--display-name", $applicationname,
        "--sign-in-audience", "AzureADMyOrg",
        "--output", "json",
        "--only-show-errors"
    )

    $application = $applicationjson | convertfrom-json

    $applicationid       = $application.appid
    $applicationobjectid = $application.id

    write-host "application registration created." -foregroundcolor green
}

write-host "application client id: $applicationid"

# -----------------------------------------------------------
#        create or retrieve service principal
# -----------------------------------------------------------

write-host ""
write-host "creating service principal..." -foregroundcolor yellow

$existingserviceprincipaljson = invoke-azurecli -arguments @(
    "ad", "sp", "list",
    "--filter", "appId eq '$applicationid'",
    "--query", "[0]",
    "--output", "json",
    "--only-show-errors"
)

$existingserviceprincipal = $existingserviceprincipaljson | convertfrom-json

if (
    $null -ne $existingserviceprincipal -and
    -not [string]::isnullorwhitespace($existingserviceprincipal.id)
) {
    $serviceprincipalobjectid = $existingserviceprincipal.id

    write-host "service principal already exists." -foregroundcolor darkyellow
}
else {
    invoke-azurecli -arguments @(
        "ad", "sp", "create",
        "--id", $applicationid,
        "--output", "none",
        "--only-show-errors"
    ) | out-null

    $serviceprincipalobjectid = $null

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        start-sleep -seconds 5

        try {
            $serviceprincipalobjectid = invoke-azurecli -arguments @(
                "ad", "sp", "show",
                "--id", $applicationid,
                "--query", "id",
                "--output", "tsv",
                "--only-show-errors"
            )

            $serviceprincipalobjectid =
                "$serviceprincipalobjectid".trim()
        }
        catch {
            $serviceprincipalobjectid = $null
        }

        if (
            -not [string]::isnullorwhitespace(
                $serviceprincipalobjectid
            )
        ) {
            break
        }
    }

    if (
        [string]::isnullorwhitespace(
            $serviceprincipalobjectid
        )
    ) {
        throw "service principal was created but could not be queried."
    }

    write-host "service principal created." -foregroundcolor green
}

write-host "service principal object id: $serviceprincipalobjectid"

# -----------------------------------------------------------
#        set optional federated identity credential
# -----------------------------------------------------------

if (
    -not [string]::isnullorwhitespace($githubowner) -and
    -not [string]::isnullorwhitespace($githubrepo)
) {
    write-host ""
    write-host "configuring app registration for GitHub Actions OIDC..." `
        -foregroundcolor yellow

    $federatedcredentialname = "github-$githubenv"
    $federatedsubject =
        "repo:${githubowner}/${githubrepo}:environment:${githubenv}"

    $existingcredentialname = invoke-azurecli -arguments @(
        "ad", "app", "federated-credential", "list",
        "--id", $applicationobjectid,
        "--query", "[?name=='$federatedcredentialname'].name | [0]",
        "--output", "tsv",
        "--only-show-errors"
    )

    if (
        -not [string]::isnullorwhitespace(
            "$existingcredentialname"
        )
    ) {
        write-host "federated credential already exists." `
            -foregroundcolor darkyellow
    }
    else {
        $federatedcredential = @{
            name        = $federatedcredentialname
            issuer      = "https://token.actions.githubusercontent.com"
            subject     = $federatedsubject
            description = `
                "GitHub Actions OIDC for $githubowner/$githubrepo environment $githubenv"
            audiences   = @(
                "api://AzureADTokenExchange"
            )
        }

        $temporarycredentialfile = join-path `
            ([system.io.path]::gettemppath()) `
            "github-federated-credential-$([guid]::newguid().tostring('N')).json"

        try {
            $federatedcredential |
                convertto-json -depth 5 |
                set-content `
                    -path $temporarycredentialfile `
                    -encoding utf8

            invoke-azurecli -arguments @(
                "ad", "app", "federated-credential", "create",
                "--id", $applicationobjectid,
                "--parameters", "@$temporarycredentialfile",
                "--output", "none",
                "--only-show-errors"
            ) | out-null
        }
        finally {
            remove-item `
                -path $temporarycredentialfile `
                -force `
                -erroraction silentlycontinue
        }

        write-host "federated credential created." -foregroundcolor green
    }

    write-host "federated credential subject: $federatedsubject"
}
elseif (
    -not [string]::isnullorwhitespace($githubowner) -or
    -not [string]::isnullorwhitespace($githubrepo)
) {
    throw "githubowner and githubrepo must both be provided or both omitted."
}
else {
    write-host ""
    write-host "GitHub owner and repository were not supplied." `
        -foregroundcolor darkyellow
    write-host "skipping creation of the federated credential."
}

# -----------------------------------------------------------
#        grant contributor over resource group
# -----------------------------------------------------------

write-host ""
write-host "assigning Contributor to the service principal on the Terraform resource group..." `
    -foregroundcolor yellow

$existingcontributorassignment = invoke-azurecli -arguments @(
    "role", "assignment", "list",
    "--assignee-object-id", $serviceprincipalobjectid,
    "--role", "Contributor",
    "--scope", $resourcegroupid,
    "--query", "[0].id",
    "--output", "tsv",
    "--only-show-errors"
)

if (
    [string]::isnullorwhitespace(
        "$existingcontributorassignment"
    )
) {
    invoke-azurecli -arguments @(
        "role", "assignment", "create",
        "--assignee-object-id", $serviceprincipalobjectid,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", "Contributor",
        "--scope", $resourcegroupid,
        "--output", "none",
        "--only-show-errors"
    ) | out-null

    write-host "Contributor assignment created." -foregroundcolor green
}
else {
    write-host "Contributor assignment already exists." `
        -foregroundcolor darkyellow
}

# -----------------------------------------------------------
#                 create storage account
# -----------------------------------------------------------

Write-Host ""
Write-Host "checking for storage account '$storageAccountName'..." `
    -ForegroundColor Yellow

# Do not use Invoke-AzureCli here because ResourceNotFound is an expected
# result when the storage account does not exist yet.
$existingStorageAccount = & az storage account show `
    --name $storageAccountName `
    --resource-group $resourceGroupName `
    --query name `
    --output tsv `
    --only-show-errors 2>$null

$storageAccountExists = (
    $LASTEXITCODE -eq 0 -and
    -not [string]::IsNullOrWhiteSpace("$existingStorageAccount")
)

if (-not $storageAccountExists) {
    Write-Host "creating storage account '$storageAccountName'..." `
        -ForegroundColor Yellow

    Invoke-AzureCli -Arguments @(
        "storage", "account", "create",
        "--name", $storageAccountName,
        "--resource-group", $resourceGroupName,
        "--location", $location,
        "--sku", "Standard_LRS",
        "--kind", "StorageV2",
        "--https-only", "true",
        "--min-tls-version", "TLS1_2",
        "--allow-blob-public-access", "false",
        "--allow-cross-tenant-replication", "false",
        "--default-action", "Allow",
        "--tags",
            "managed-by=azure-bootstrap-script",
            "purpose=terraform-backend",
            "project=resume-as-code",
        "--output", "none"
    )

    Write-Host "storage account creation request completed." `
        -ForegroundColor Green
}
else {
    Write-Host "storage account already exists." `
        -ForegroundColor DarkYellow
}

# Azure may briefly return ResourceNotFound after the create command completes.
# Poll until the account is queryable and provisioning has succeeded.

Write-Host "waiting for storage account provisioning..." `
    -ForegroundColor Yellow

$storageAccountId = $null
$provisioningState = $null
$maximumAttempts = 60
$delaySeconds = 5

for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
    $storageAccountJson = & az storage account show `
        --name $storageAccountName `
        --resource-group $resourceGroupName `
        --output json `
        --only-show-errors 2>$null

    if ($LASTEXITCODE -eq 0 -and
        -not [string]::IsNullOrWhiteSpace("$storageAccountJson")) {

        $storageAccount = $storageAccountJson | ConvertFrom-Json

        $storageAccountId = $storageAccount.id
        $provisioningState = $storageAccount.provisioningState

        Write-Host (
            "storage account provisioning state: {0} ({1}/{2})" -f `
                $provisioningState,
                $attempt,
                $maximumAttempts
        )

        if ($provisioningState -eq "Succeeded") {
            break
        }

        if ($provisioningState -eq "Failed") {
            throw @"
Azure reported that storage account provisioning failed.

Storage account: $storageAccountName
Resource group: $resourceGroupName
"@
        }
    }
    else {
        Write-Host (
            "storage account is not queryable yet ({0}/{1})" -f `
                $attempt,
                $maximumAttempts
        )
    }

    Start-Sleep -Seconds $delaySeconds
}

if ([string]::IsNullOrWhiteSpace("$storageAccountId") -or
    $provisioningState -ne "Succeeded") {

    throw @"
Timed out waiting for the storage account to become ready.

Storage account: $storageAccountName
Resource group: $resourceGroupName
Last provisioning state: $provisioningState
"@
}

$storageAccountId = "$storageAccountId".Trim()

Write-Host "storage account is ready." -ForegroundColor Green
Write-Host "storage account ID: $storageAccountId"

# -----------------------------------------------------------
#                 enable blob versioning
# -----------------------------------------------------------

write-host ""
write-host "enabling blob versioning..." -foregroundcolor yellow

invoke-azurecli -arguments @(
    "storage", "account", "blob-service-properties", "update",
    "--account-name", $storageaccountname,
    "--resource-group", $resourcegroupname,
    "--enable-versioning", "true",
    "--output", "none",
    "--only-show-errors"
) | out-null

write-host "blob versioning enabled." -foregroundcolor green

# -----------------------------------------------------------
#                 create state container
# -----------------------------------------------------------

write-host ""
write-host "creating or verifying '$containername' container..." `
    -foregroundcolor yellow

$storageaccountkey = invoke-azurecli -arguments @(
    "storage", "account", "keys", "list",
    "--account-name", $storageaccountname,
    "--resource-group", $resourcegroupname,
    "--query", "[0].value",
    "--output", "tsv",
    "--only-show-errors"
)

$storageaccountkey = "$storageaccountkey".trim()

invoke-azurecli -arguments @(
    "storage", "container", "create",
    "--name", $containername,
    "--account-name", $storageaccountname,
    "--account-key", $storageaccountkey,
    "--public-access", "off",
    "--output", "none",
    "--only-show-errors"
) | out-null

remove-variable storageaccountkey -erroraction silentlycontinue

write-host "state container created or verified." -foregroundcolor green

$containerscope =
    "$storageaccountid/blobServices/default/containers/$containername"

# -----------------------------------------------------------
#       assign blob permissions to service principal
# -----------------------------------------------------------

write-host ""
write-host "assigning Storage Blob Data Contributor to the state container..." `
    -foregroundcolor yellow

$existingblobassignment = invoke-azurecli -arguments @(
    "role", "assignment", "list",
    "--assignee-object-id", $serviceprincipalobjectid,
    "--role", "Storage Blob Data Contributor",
    "--scope", $containerscope,
    "--query", "[0].id",
    "--output", "tsv",
    "--only-show-errors"
)

if (
    [string]::isnullorwhitespace(
        "$existingblobassignment"
    )
) {
    invoke-azurecli -arguments @(
        "role", "assignment", "create",
        "--assignee-object-id", $serviceprincipalobjectid,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", "Storage Blob Data Contributor",
        "--scope", $containerscope,
        "--output", "none",
        "--only-show-errors"
    ) | out-null

    write-host "Storage Blob Data Contributor assignment created." `
        -foregroundcolor green
}
else {
    write-host "Storage Blob Data Contributor assignment already exists." `
        -foregroundcolor darkyellow
}

# -----------------------------------------------------------
#                        results
# -----------------------------------------------------------

$backendconfiguration = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$resourcegroupname"
    storage_account_name = "$storageaccountname"
    container_name       = "$containername"
    key                  = "resume-as-code.tfstate"
    use_azuread_auth     = true
  }
}
"@

write-host ""
write-host "bootstrap complete" -foregroundcolor green
write-host "==================" -foregroundcolor green
write-host ""
write-host "application name:       $applicationname"
write-host "azure client id:         $applicationid"
write-host "azure tenant id:         $tenantid"
write-host "azure subscription id:   $subscriptionid"
write-host "service principal id:    $serviceprincipalobjectid"
write-host "resource group:          $resourcegroupname"
write-host "storage account:         $storageaccountname"
write-host "state container:         $containername"
write-host ""
write-host "terraform backend configuration snippet:" `
    -foregroundcolor cyan
write-host ""
write-host $backendconfiguration
write-host ""
write-host "recommended GitHub repository variables:" `
    -foregroundcolor cyan
write-host ""
write-host "AZURE_CLIENT_ID=$applicationid"
write-host "AZURE_TENANT_ID=$tenantid"
write-host "AZURE_SUBSCRIPTION_ID=$subscriptionid"
write-host ""
