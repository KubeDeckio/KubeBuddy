# Main Script: AKS Best Practices Checklist

param (
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ClusterName,
    [string]$OutputFormat = "CLI"
)

# Authenticate with Azure and fetch cluster details
function Authenticate {
    Write-Host "Authenticating with Azure..." -ForegroundColor Cyan
    az login --output none
    az account set --subscription $SubscriptionId
    if ($?) {
        Write-Host "Authentication successful." -ForegroundColor Green
    }
    else {
        Write-Host "Authentication failed. Exiting..." -ForegroundColor Red
        exit 1
    }
}

function Get-AKSClusterInfo {
    Write-Host "Fetching AKS cluster details..." -ForegroundColor Cyan
    $clusterInfo = az aks show --resource-group $ResourceGroup --name $ClusterName --output json | ConvertFrom-Json
    if (-not $clusterInfo) {
        Write-Host "Error: Failed to fetch cluster details. Exiting..." -ForegroundColor Red
        exit 1
    }
    return $clusterInfo
}

function Get-KubeResources {
    Write-Host "Fetching Kubernetes cluster resource data..." -ForegroundColor Cyan
    $kubeData = @{
        ConstraintTemplates = kubectl get constrainttemplates -A -o json | ConvertFrom-Json
    }
    return $kubeData
}

# Clear any existing check variables
Get-Variable -Name "*Checks" -ErrorAction SilentlyContinue | Remove-Variable -Force

# Import all check definitions from the Checks folder.
Get-ChildItem -Path ".\Checks" -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

# Combine all checks from variables ending with 'Checks'
$checks = @()
Get-Variable -Name "*Checks" | ForEach-Object {
    $checks += $_.Value
}

# Remove duplicate checks based on their ID
$checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }

function Run-Checks {
    param ($clusterInfo)
    Write-Host "Running best practice checks..." -ForegroundColor Cyan

    $categories = @{
        "Security"             = @();
        "Networking"           = @();
        "Resource Management"  = @();
        "Monitoring & Logging" = @();
        "Identity & Access"    = @();
        "Disaster Recovery"    = @();
        "Best Practices"       = @();
    }

    foreach ($check in $checks) {
        try {
            $value = $check.Value
            $name = $check.Name

            # Write-Host "Check Name: $name Check Value: $value"

            if ($value -eq $check.Expected) {
                $categories[$check.Category] += [PSCustomObject]@{
                    ID             = $check.ID;
                    Check          = $check.Name;
                    Status         = "✅ PASS";
                    Recommendation = "$($check.Name) is enabled."
                }
            }
            else {
                $categories[$check.Category] += [PSCustomObject]@{
                    ID             = $check.ID;
                    Check          = $check.Name;
                    Status         = "❌ FAIL";
                    Recommendation = $check.FailMessage
                }
            }
        }
        catch {
            Write-Host "Error processing check: $($check.Name). Skipping... $_" -ForegroundColor Red
        }
    }
    return $categories
}

function Display-Results {
    param ([hashtable]$categories)
    Write-Host "AKS Best Practices Checklist Results:" -ForegroundColor Yellow

    $passCount = 0
    $failCount = 0

    foreach ($category in $categories.Keys) {
        Write-Host "`n=== $category ===" -ForegroundColor Cyan
        $categories[$category] | Format-Table ID, Check, Status, Recommendation -AutoSize

        $passCount += ($categories[$category] | Where-Object { $_.Status -eq "✅ PASS" }).Count
        $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
    }

# Calculate pass/fail totals and overall rating (same logic as before)
$passCount = ($categories.Values | ForEach-Object { $_ } | Where-Object { $_.Status -eq "✅ PASS" }).Count
$failCount = ($categories.Values | ForEach-Object { $_ } | Where-Object { $_.Status -eq "❌ FAIL" }).Count
$total = $passCount + $failCount

if ($total -eq 0) {
    $rating = "N/A"
    $score = 0
}
else {
    $score = ($passCount / $total) * 100
    if ($passCount -eq $total) {
        $rating = "A++"
    }
    elseif ($score -ge 90) {
        $rating = "A"
    }
    elseif ($score -ge 80) {
        $rating = "B"
    }
    elseif ($score -ge 70) {
        $rating = "C"
    }
    elseif ($score -ge 60) {
        $rating = "D"
    }
    else {
        $rating = "F"
    }
}

# Choose a color based on the rating
switch ($rating) {
    "A++" { $ratingColor = "Green" }
    "A"  { $ratingColor = "Green" }
    "B"  { $ratingColor = "Yellow" }
    "C"  { $ratingColor = "Yellow" }
    "D"  { $ratingColor = "DarkYellow" }
    "F"  { $ratingColor = "Red" }
    default { $ratingColor = "Gray" }
}

# Build the simple summary output
Write-Host "`nSummary & Rating:" -ForegroundColor Green

# Header line
$header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
$separator = "============================================================"

# Data row
$row = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f ("✅ " + $passCount), ("❌ " + $failCount), $total, ([math]::Round($score,2)), $rating

Write-Host $header -ForegroundColor Cyan
Write-Host $separator -ForegroundColor Cyan
Write-Host $row -ForegroundColor $ratingColor


}

# Main Execution
#Authenticate
$clusterInfo = Get-AKSClusterInfo
$kubeResources = Get-KubeResources
$checkResults = Run-Checks -clusterInfo $clusterInfo
Display-Results -categories $checkResults
