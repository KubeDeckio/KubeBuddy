# Main Script: AKS Best Practices Checklist

param (
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ClusterName,
    [switch]$FailedOnly,
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
                    Severity       = $check.Severity;
                    Status         = "✅ PASS";
                    Recommendation = "$($check.Name) is enabled.";
                    URL            = $check.URL
                }
            }
            else {
                $categories[$check.Category] += [PSCustomObject]@{
                    ID             = $check.ID;
                    Check          = $check.Name;
                    Severity       = $check.Severity;
                    Status         = "❌ FAIL";
                    Recommendation = $check.FailMessage
                    URL            = $check.URL
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
    param (
        [hashtable]$categories,
        [switch]$FailedOnly
    )
    Write-Host "AKS Best Practices Checklist Results:" -ForegroundColor Yellow

    $passCount = 0
    $failCount = 0

    foreach ($category in $categories.Keys) {
        # Filter the checks if -FailedOnly was specified
        $checks = $categories[$category]
        if ($FailedOnly) {
            $checks = $checks | Where-Object { $_.Status -eq "❌ FAIL" }
        }
        if ($checks.Count -gt 0) {
            Write-Host "`n=== $category ===" -ForegroundColor Cyan
            $checks | Format-Table ID, Check, Severity, Status, Recommendation, URL -AutoSize
        }
        # Always count all checks (or only failed if desired)
        if ($FailedOnly) {
            $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
        }
        else {
            $passCount += ($categories[$category] | Where-Object { $_.Status -eq "✅ PASS" }).Count
            $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
        }
    }

    # Recalculate totals based on the switch
    if ($FailedOnly) {
        $total = $failCount
        $score = 0
        $rating = "F"
        $ratingColor = "Red"
    }
    else {
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
    
        switch ($rating) {
            "A++" { $ratingColor = "Green" }
            "A"  { $ratingColor = "Green" }
            "B"  { $ratingColor = "Yellow" }
            "C"  { $ratingColor = "Yellow" }
            "D"  { $ratingColor = "DarkYellow" }
            "F"  { $ratingColor = "Red" }
            default { $ratingColor = "Gray" }
        }
    }

    # Build the simple summary output
    Write-Host "`nSummary & Rating:" -ForegroundColor Green

    $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
    $separator = "============================================================"
    $row = if ($FailedOnly) {
                # For failed-only view, we show pass as 0
                "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f ("✅ 0"), ("❌ " + $failCount), $failCount, ([math]::Round(0,2)), $rating
           }
           else {
                "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f ("✅ " + $passCount), ("❌ " + $failCount), $total, ([math]::Round($score,2)), $rating
           }

    Write-Host $header -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan
    Write-Host $row -ForegroundColor $ratingColor
}


# Main Execution
#Authenticate
$clusterInfo = Get-AKSClusterInfo
$kubeResources = Get-KubeResources
$checkResults = Run-Checks -clusterInfo $clusterInfo -FailedOnly $FailedOnly
Display-Results -categories $checkResults
