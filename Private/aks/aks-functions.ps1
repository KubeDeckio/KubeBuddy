function Invoke-AKSBestPractices {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [object]$KubeData
    )

    function Validate-Context {
        param ($ResourceGroup, $ClusterName)
        if ($KubeData) { return $true }

        $currentContext = kubectl config current-context
        $aksContext = az aks show --resource-group $ResourceGroup --name $ClusterName --query "name" -o tsv --only-show-errors

        if ($Global:MakeReport) {
            Write-Host "🔄 Checking Kubernetes context..." -ForegroundColor Cyan
            Write-Host "   - Current context: '$currentContext'" -ForegroundColor Yellow
            Write-Host "   - Expected AKS cluster: '$aksContext'" -ForegroundColor Yellow

            if ($currentContext -eq $aksContext) {
                Write-Host "✅ Kubernetes context matches. Proceeding with the scan." -ForegroundColor Green
                return $true
            } else {
                Write-Host "⚠️ WARNING: Context mismatch." -ForegroundColor Red
                Write-ToReport "   - Skipping validation due to mismatched context."
                return $false
            }
        }

        $msg = @(
            "🔄 Checking your Kubernetes context...",
            "",
            "   - You're currently using context: '$currentContext'.",
            "   - The expected AKS cluster context is: '$aksContext'.",
            ""
        )

        if ($currentContext -eq $aksContext) {
            $msg += @("✅ The context is correct.")
            Write-SpeechBubble -msg $msg -color "Green" -icon "🤖"
            return $true
        } else {
            $msg += @(
                "⚠️ WARNING: Context mismatch!",
                "",
                "❌ Commands may target the wrong cluster.",
                "",
                "💡 Run: kubectl config use-context $aksContext"
            )
            Write-SpeechBubble -msg $msg -color "Yellow" -icon "🤖" -lastColor "Red"
            if ($yes) {
                Write-SpeechBubble -msg @("🤖 Skipping context confirmation.") -color "Red" -icon "🤖"
                return $true
            }
            Write-SpeechBubble -msg @("🤖 Please confirm if you want to continue.") -color "Yellow" -icon "🤖"
            $confirmation = Read-Host "🤖 Continue anyway? (yes/no)"
            Clear-Host
            if ($confirmation -match "^(y|yes)$") {
                Write-SpeechBubble -msg @("⚠️ Proceeding despite mismatch...") -color "Yellow" -icon "🤖"
                return $true
            } else {
                Write-SpeechBubble -msg @("❌ Exiting to prevent incorrect execution.") -color "Red" -icon "🤖"
                exit 1
            }
        }
    }

    function Get-AKSClusterInfo {
        param (
            [string]$SubscriptionId,
            [string]$ResourceGroup,
            [string]$ClusterName,
            [object]$KubeData
        )

        Write-Host -NoNewline "`n🤖 Fetching AKS cluster details..." -ForegroundColor Cyan

        $clusterInfo = $null
    $constraints = @()

    try {
        if ($KubeData -and $KubeData.AksCluster -and $KubeData.Constraints) {
            $clusterInfo = $KubeData.AksCluster
            $constraints = $KubeData.Constraints
            Write-Host "`r🤖 Using cached AKS cluster data. " -ForegroundColor Green
        } else {
            $clusterInfo = az aks show --resource-group $ResourceGroup --name $ClusterName --output json --only-show-errors | ConvertFrom-Json
            Write-Host "`r🤖 Live cluster data fetched.    " -ForegroundColor Green

            Write-Host -NoNewline "`n🤖 Fetching Kubernetes constraints..." -ForegroundColor Cyan
            $constraints = kubectl get constraints -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
            Write-Host "`r🤖 Constraints fetched." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "`r❌ Error retrieving AKS or constraint data: $_" -ForegroundColor Red
        return $null
    }

# Attach constraints regardless of source
$clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }

return $clusterInfo
    }

    # Collect all checks
    $checks = @()
    Get-Variable -Name "*Checks" | ForEach-Object {
        $checks += $_.Value
    }
    $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }

    function Run-Checks {
        param ($clusterInfo)
        if (-not $HtmlReport){
        Write-Host -NoNewline "`n🤖 Running best practice checks..." -ForegroundColor Cyan
        }
        if ($Global:MakeReport) {
            Write-ToReport "`n[✅ AKS Best Practices Check]`n"
        }

        $categories = @{
            "Security"             = @();
            "Networking"           = @();
            "Resource Management"  = @();
            "Monitoring & Logging" = @();
            "Identity & Access"    = @();
            "Disaster Recovery"    = @();
            "Best Practices"       = @();
        }

        if (-not $Global:MakeReport -and -not $HtmlReport -and -not $jsonReport) { Clear-Host }

        foreach ($check in $checks) {
            try {
                $value = if ($check.Value -is [scriptblock]) {
                    & $check.Value
                } elseif ($check.Value -match "^(True|False|[0-9]+)$") {
                    [bool]([System.Convert]::ChangeType($check.Value, [boolean]))
                } else {
                    Invoke-Expression ($check.Value -replace '\$clusterInfo', '$clusterInfo')
                }

                $result = if ($value -eq $check.Expected) { "✅ PASS" } else { "❌ FAIL" }

                $categories[$check.Category] += [PSCustomObject]@{
                    ID             = $check.ID;
                    Check          = $check.Name;
                    Severity       = $check.Severity;
                    Category       = $check.Category;
                    Status         = $result;
                    Recommendation = if ($result -eq "✅ PASS") { "$($check.Name) is enabled." } else { $check.FailMessage }
                    URL            = $check.URL
                }

                if ($Global:MakeReport) {
                    Write-ToReport "[$($check.Category)] $($check.Name) - $result"
                    Write-ToReport "   🔹 Severity: $($check.Severity)"
                    Write-ToReport "   🔹 Recommendation: $($categories[$check.Category][-1].Recommendation)"
                    Write-ToReport "   🔹 Info: $($check.URL)`n"
                }
            }
            catch {
                Write-Host "Error processing check: $($check.Name). $_" -ForegroundColor Red
            }
        }

        return $categories
    }

    function Display-Results {
        param (
            [hashtable]$categories,
            [switch]$FailedOnly,
            [switch]$Html
        )
    
        $passCount = 0
        $failCount = 0
        $reportData = @()  # ✅ Initialize empty array to prevent null reference
    
        foreach ($category in $categories.Keys) {
            # Filter checks if -FailedOnly is specified
            $checks = $categories[$category]
            if ($FailedOnly) {
                $checks = $checks | Where-Object { $_.Status -eq "❌ FAIL" }
            }
    
            if ($checks.Count -gt 0 -and -not $Html -and -not $Global:MakeReport) {
                Write-Host "`n=== $category ===             " -ForegroundColor Cyan
                $checks | Format-Table ID, Check, Severity, Category, Status, Recommendation, URL -AutoSize
    
                # ✅ Show "Press any key to continue..." message
                Write-Host "`nPress any key to continue..." -ForegroundColor Magenta -NoNewline
    
                # ✅ Wait for keypress
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
                # ✅ Move cursor up one line and clear it
                if ($Host.Name -match "ConsoleHost") {
                    # Windows Terminal / Standard PowerShell console
                    [Console]::SetCursorPosition(0, [Console]::CursorTop - 1)
                    Write-Host (" " * 50) -NoNewline
                    [Console]::SetCursorPosition(0, [Console]::CursorTop)
                }
                else {
                    # ANSI escape codes for clearing a line (Linux/macOS)
                    Write-Host "`e[1A`e[2K" -NoNewline
                }
            }
            else {
                # ✅ Append check results to $reportData
                $reportData += $checks | Select-Object ID, Check, Severity, Category, Status, Recommendation, URL
            }
    
            # Count passed and failed checks
            $passCount += ($categories[$category] | Where-Object { $_.Status -eq "✅ PASS" }).Count
            $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
        }
    
        # **Summary Calculation**
        $total = $passCount + $failCount
        $score = if ($total -eq 0) { 0 } else { [math]::Round(($passCount / $total) * 100, 2) }
    
        # **Fix: Pick only the first rating letter**
        $rating = @(switch ($score) {
                { $_ -ge 90 } { "A" }
                { $_ -ge 80 } { "B" }
                { $_ -ge 70 } { "C" }
                { $_ -ge 60 } { "D" }
                default { "F" }
            })[0]  # Picks only the FIRST rating letter
    
        # **Assign Color for Rating**
        $ratingColor = switch ($rating) {
            "A" { "Green" }
            "B" { "Yellow" }
            "C" { "DarkYellow" }
            "D" { "Red" }
            "F" { "DarkRed" }
            default { "Gray" }
        }
    
        # **CLI Output for Summary**
        if (-not $Html -and -not $Global:MakeReport) {
            Write-Host "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-Host $header -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Cyan
            Write-Host "$row " -NoNewline
            Write-Host "$rating" -ForegroundColor $ratingColor # Rating is colored correctly
        }

        if ($global:MakeReport) {
            Write-ToReport "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-ToReport $header
            Write-ToReport $separator
            Write-ToReport "$row " -NoNewline
            Write-ToReport "$rating"
        }
    
        # ✅ **HTML Output: Return Key Values**
        if ($Html) {
            $htmlTable = if ($reportData.Count -gt 0) {
                $sortedReportData = $reportData | Sort-Object @{Expression = { $_.Status -eq "❌ FAIL" } ; Descending = $true }, Category
                $sortedReportData | ConvertTo-Html -Fragment -Property ID, Check, Severity, Category, Status, Recommendation, URL | Out-String
            }
            else {
                "<p><strong>No best practice violations detected.</strong></p>"
            }
    
            return [PSCustomObject]@{
                Passed = $passCount
                Failed = $failCount
                Total  = $total
                Score  = $score
                Rating = "$rating"
                Data   = $htmlTable
            }
        }
    }

    # Main Execution Flow
    if ($Global:MakeReport) {
        Write-Host "`n🤖 Starting AKS Best Practices Check...`n" -ForegroundColor Green
    }

    Validate-Context -ResourceGroup $ResourceGroup -ClusterName $ClusterName
    $clusterInfo = Get-AKSClusterInfo -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData $KubeData
    $checkResults = Run-Checks -clusterInfo $clusterInfo

    if ($Html) {
        return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html
    } else {
        Display-Results -categories $checkResults -FailedOnly:$FailedOnly
        if (-not $Global:MakeReport) {
            Write-Host "`nPress Enter to return to the menu..." -ForegroundColor Yellow
            Read-Host
        }
    }

    if ($Global:MakeReport) {
        Write-Host "`n✅ AKS Best Practices Check Completed.`n" -ForegroundColor Green
    }
}
