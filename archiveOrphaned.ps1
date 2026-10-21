#  Script to Archive all Orphaned configuration items on the IT Glue account 
#  Author: Bart Jozwiak
#---------------------------------------------------------------------


# --- Prompt for API key ---
$ApiKey = Read-Host "Enter your IT Glue API key"

# --- Configuration ---
$BaseUrl  = "https://api.eu.itglue.com"
$PageSize = 100

Write-Host "Scanning for orphaned configurations..." -ForegroundColor Cyan

$page = 1
$OrphanedConfigs = @()
$scanned = 0

do {
    $response = Invoke-RestMethod -Uri "$BaseUrl/configurations?page[size]=$PageSize&page[number]=$page&include=adapters_resources" `
        -Headers @{ "x-api-key" = $ApiKey; "Accept" = "application/json" } `
        -Method Get -ErrorAction Stop

    if (-not $response.data) { break }

    $pageCount = $response.data.Count
    $scanned += $pageCount

    # --- Progress display ---
    Write-Progress -Activity "Scanning configurations..." -Status "Page $page ($scanned scanned so far)" -PercentComplete (($pageCount / $PageSize) * 100)

    foreach ($config in $response.data) {
        $id = $config.id
        $name = $config.attributes.name
        $archived = $config.attributes.archived
        $organization = $config.attributes.'organization-name'

        $isOrphaned = $false

        # Get adapter IDs related to this config
        $adapterIds = @()
        if ($config.relationships.'adapters-resources') {
            $adapterIds = $config.relationships.'adapters-resources'.data.id
        }

        foreach ($adapterId in $adapterIds) {
            # Find the adapter in included array
            $adapter = $response.included | Where-Object { $_.type -eq "adapters-resources" -and $_.id -eq $adapterId }
            if ($adapter -and $adapter.attributes.orphaned -eq $true) {
                $isOrphaned = $true
                break
            }
        }

        if ($isOrphaned -and -not $archived) {
            $OrphanedConfigs += [PSCustomObject]@{
                ID = $id
                Name = $name
                Organization = $organization
            }
        }
    }

    $page++
}
while ($response.links.next)

Write-Progress -Activity "Scanning configurations..." -Completed

$total = $OrphanedConfigs.Count
Write-Host ""
Write-Host "Scan complete. Scanned $scanned configuration(s)." -ForegroundColor Cyan
Write-Host "Found $total orphaned configuration(s)." -ForegroundColor Yellow

if ($total -eq 0) {
    Write-Host "No orphaned configurations to archive. Exiting." -ForegroundColor Green
    exit
}

# --- Print table of configs to be archived ---
Write-Host "`nConfigurations to be archived:" -ForegroundColor Cyan
$OrphanedConfigs | Format-Table -Property ID, Name, Organization -AutoSize

# --- Confirm before archiving ---
$confirm = Read-Host "`nArchive these $total orphaned configurations? (Y/N)"
if ($confirm -notin @("Y","y")) {
    Write-Host "Operation cancelled." -ForegroundColor Red
    exit
}

# --- Archive each orphaned config ---
$count = 0
foreach ($config in $OrphanedConfigs) {
    $count++
    Write-Progress -Activity "Archiving orphaned configurations..." -Status "Processing $count of $total" -PercentComplete ([math]::Round(($count/$total)*100,1))

    $body = @{
        data = @{
            type = "configurations"
            id = $config.ID
            attributes = @{
                archived = $true
            }
        }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri "$BaseUrl/configurations/$($config.ID)" `
            -Headers @{ "x-api-key" = $ApiKey; "Content-Type" = "application/json" } `
            -Method Patch -Body $body -ErrorAction Stop

        Write-Host "Archived configuration ID: $($config.ID) Name: $($config.Name)"
    }
    catch {
        Write-Host "Error archiving configuration ID: $($config.ID) Name: $($config.Name)"
    }
}

Write-Progress -Activity "Archiving orphaned configurations..." -Completed
Write-Host "All done. Archived $total configuration(s)." -ForegroundColor Green
