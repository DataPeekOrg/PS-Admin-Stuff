<#
.SYNOPSIS
    Azure Automation Runbook: Query CrowdStrike Falcon by hostname using PSFalcon 
    and hide ALL matching devices (including multiples/duplicates) if found.

.DESCRIPTION
    - Fully non-interactive
    - Pulls Falcon credentials from Azure Key Vault
    - Uses Managed Identity
    - Finds and hides **every** device matching the exact hostname (great for cleaning duplicates)
    - Excellent logging for Automation job history
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Hostname,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [string]$ClientIdSecretName = "Falcon-ClientId",
    [string]$ClientSecretSecretName = "Falcon-ClientSecret",
    [string]$FalconCloud = "us-1"   # us-2, eu-1, etc. as needed
)

Write-Output "=== CrowdStrike Device Hide Automation Started ==="
Write-Output "Target Hostname : $Hostname (will hide ALL matches/duplicates)"
Write-Output "Key Vault       : $KeyVaultName"
Write-Output "Falcon Cloud    : $FalconCloud"
Write-Output "-------------------------------------------------"

# Connect to Azure using Managed Identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "[OK] Connected to Azure via Managed Identity"
}
catch {
    Write-Error "[FAIL] Failed to connect to Azure: $($_.Exception.Message)"
    throw
}

# Retrieve Falcon credentials from Key Vault
try {
    $ClientId = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ClientIdSecretName -AsPlainText -ErrorAction Stop
    $ClientSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ClientSecretSecretName -AsPlainText -ErrorAction Stop
    Write-Output "[OK] Retrieved Falcon API credentials from Key Vault"
}
catch {
    Write-Error "[FAIL] Failed to retrieve secrets from Key Vault: $($_.Exception.Message)"
    throw
}

# Import PSFalcon
Import-Module PSFalcon -ErrorAction Stop
Write-Output "[OK] PSFalcon module loaded"

# Authenticate to CrowdStrike
try {
    Request-FalconToken -ClientId $ClientId -ClientSecret $ClientSecret -Cloud $FalconCloud -ErrorAction Stop
    Write-Output "[OK] Authenticated to CrowdStrike Falcon"
}
catch {
    Write-Error "[FAIL] Failed to obtain Falcon token: $($_.Exception.Message)"
    throw
}

# Search for ALL devices with this hostname (handles duplicates)
Write-Output "Searching for hostname: $Hostname ..."
$devices = Get-FalconHost -Filter "hostname:'$Hostname'" -Detailed -All

if (-not $devices -or $devices.Count -eq 0) {
    Write-Output "[INFO] No devices found with hostname '$Hostname'. Nothing to hide."
    Write-Output "=== Runbook Completed Successfully ==="
    return
}

# Show what was found
Write-Output "[INFO] Found $($devices.Count) device(s) matching hostname '$Hostname' (including any duplicates):"
$devices | Select-Object hostname, device_id, platform_name, os_version, last_seen, status |
    Format-Table -AutoSize | Out-String | Write-Output

$deviceIds = $devices.device_id

# Hide ALL matching devices
try {
    Write-Output "[ACTION] Submitting hide_host action for $($deviceIds.Count) device(s)..."
    $null = Invoke-FalconHostAction -Name hide_host -Ids $deviceIds
    Write-Output "[SUCCESS] Hide action successfully submitted to CrowdStrike for all matching devices."
    Write-Output "All devices with this hostname will be removed from the main Host Management view."
}
catch {
    Write-Error "[FAIL] Failed to hide device(s): $($_.Exception.Message)"
    throw
}

Write-Output "=== Runbook Completed Successfully ==="
