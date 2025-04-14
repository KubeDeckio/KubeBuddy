function Invoke-AKSBestPractices {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [switch]$json,
        [object]$KubeData
    )

    function Validate-Context {
        param ($ResourceGroup, $ClusterName)
        if ($KubeData) { return $true | Out-Null }

        $currentContext = kubectl config current-context
        try {
            $aksContext = az aks show --resource-group $ResourceGroup --name $ClusterName --query "name" -o tsv --only-show-errors 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $aksContext) {
                throw "Failed to retrieve AKS context. Please verify the resource group and cluster name."
            }
        }
        catch {
            Write-Error "❌ Error fetching AKS context: $_"
            throw "Critical error: Unable to continue without AKS context."
        }
        

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
                # Use Azure CLI to get an access token
                $accessToken = az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
                if (-not $accessToken) { throw "Access token not retrieved." }
    
                $headers = @{ Authorization = "Bearer $accessToken" }
                $apiVersion = "2025-01-01"
                $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ContainerService/managedClusters/${ClusterName}?api-version=${apiVersion}"
    
                $clusterInfo = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing
                Write-Host "`r🤖 Live cluster data fetched.     " -ForegroundColor Green
    
                Write-Host -NoNewline "`n🤖 Fetching Kubernetes constraints..." -ForegroundColor Cyan
                $constraints = kubectl get constraints -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
                Write-Host "`r🤖 Constraints fetched." -ForegroundColor Green
            }
    
            # Attach constraints regardless of source
            $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }
    
            return $clusterInfo
        }
        catch {
            Write-Host "`r❌ Error retrieving AKS or constraint data: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }    

    # Collect all checks
    $checks = @()
    Get-Variable -Name "*Checks" | ForEach-Object {
        $checks += $_.Value
    }
    $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }

    function Run-Checks {
        param ($clusterInfo)
        if (-not $HtmlReport -and -not $jsonReport -and -not $Global:MakeReport){
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
                    $vars = [System.Collections.Generic.List[System.Management.Automation.PSVariable]]::new()
                    $vars.Add([System.Management.Automation.PSVariable]::new('clusterInfo', $clusterInfo))
                    $check.Value.InvokeWithContext($null, $vars)
                } elseif ($check.Value -match "^(True|False|[0-9]+)$") {
                    [bool]([System.Convert]::ChangeType($check.Value, [boolean]))
                } else {
                    Invoke-Expression ($check.Value -replace '\$clusterInfo', '$clusterInfo')
                }
        
                $result = if ($value -eq $check.Expected) { "✅ PASS" } else { "❌ FAIL" }
        
                if (-not $categories.ContainsKey($check.Category)) {
                    $categories[$check.Category] = @()
                }
        
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
            [switch]$Html,
            [switch]$json
        )
    
        $passCount = 0
        $failCount = 0
        $reportData = @()
        
    
        foreach ($category in $categories.Keys) {
            $checks = $categories[$category]
            if ($FailedOnly) {
                $checks = $checks | Where-Object { $_.Status -eq "❌ FAIL" }
            }
    
            if ($checks.Count -gt 0 -and -not $Html -and -not $jsonReport -and -not $Global:MakeReport) {
                Write-Host "`n=== $category ===             " -ForegroundColor Cyan              
                $checks | Format-Table ID, Check, Severity, Category, Status, Recommendation, @{Label="URL";Expression={$_."URL"}} -AutoSize | out-string | write-host
    
                Write-Host "`nPress any key to continue..." -ForegroundColor Magenta -NoNewline
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
                if ($Host.Name -match "ConsoleHost") {
                    [Console]::SetCursorPosition(0, [Console]::CursorTop - 1)
                    Write-Host (" " * 50) -NoNewline
                    [Console]::SetCursorPosition(0, [Console]::CursorTop)
                }
                else {
                    Write-Host "`e[1A`e[2K" -NoNewline
                }
            }
            else {
                # Format URL as hyperlink for HTML output
                $reportData += $checks | Select-Object ID, Check, Severity, Category, Status, Recommendation, @{
                    Name = 'URL';
                    Expression = { if ($_.URL) { "<a href='$($_.URL)' target='_blank'>Learn More</a>" } else { "" } }
                }
            }
    
            $passCount += ($categories[$category] | Where-Object { $_.Status -eq "✅ PASS" }).Count
            $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
        }
    
        $total = $passCount + $failCount
        $score = if ($total -eq 0) { 0 } else { [math]::Round(($passCount / $total) * 100, 2) }
        $rating = @(switch ($score) {
                { $_ -ge 90 } { "A" }
                { $_ -ge 80 } { "B" }
                { $_ -ge 70 } { "C" }
                { $_ -ge 60 } { "D" }
                default { "F" }
            })[0]
    
        $ratingColor = switch ($rating) {
            "A" { "Green" }
            "B" { "Yellow" }
            "C" { "DarkYellow" }
            "D" { "Red" }
            "F" { "DarkRed" }
            default { "Gray" }
        }
    
        if (-not $Html -and -not $jsonReport -and -not $Global:MakeReport) {
            Write-Host "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-Host $header -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Cyan
            Write-Host "$row " -NoNewline
            Write-Host "$rating" -ForegroundColor $ratingColor
        }
    
        if ($Global:MakeReport) {
            Write-ToReport "`nSummary & Rating:           "
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
            Write-ToReport $header
            Write-ToReport $separator
            Write-ToReport "$row " -NoNewline
            Write-ToReport "$rating"
        }
    
        if ($Html) {
            $htmlTable = if ($reportData.Count -gt 0) {
                $sortedReportData = $reportData | Sort-Object @{Expression = { $_.Status -eq "❌ FAIL" } ; Descending = $true }, Category
                # Generate HTML table manually to prevent escaping of HTML in the URL column
                $htmlRows = $sortedReportData | ForEach-Object {
                    $id = $_.ID
                    $check = $_.Check
                    $severity = $_.Severity
                    $category = $_.Category
                    $status = $_.Status
                    $recommendation = $_.Recommendation
                    $url = $_.URL  # This is already an HTML anchor tag, do not escape
                    "<tr><td>$id</td><td>$check</td><td>$severity</td><td>$category</td><td>$status</td><td>$recommendation</td><td>$url</td></tr>"
                }
                $htmlTableContent = "<table>`n<thead><tr><th>ID</th><th>Check</th><th>Severity</th><th>Category</th><th>Status</th><th>Recommendation</th><th>URL</th></tr></thead>`n<tbody>`n" + ($htmlRows -join "`n") + "`n</tbody>`n</table>"
                $htmlTableContent
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
        Write-Host -NoNewline "`n🤖 Starting AKS Best Practices Check...`n" -ForegroundColor Cyan
    }

    Validate-Context -ResourceGroup $ResourceGroup -ClusterName $ClusterName
    $clusterInfo = Get-AKSClusterInfo -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData $KubeData

    $checkResults = Run-Checks -clusterInfo $clusterInfo


    if ($Html) {
        return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html
    } else {
        Display-Results -categories $checkResults -FailedOnly:$FailedOnly
        if (-not $Global:MakeReport -and -not $json) {
            Write-Host "`nPress Enter to return to the menu..." -ForegroundColor Yellow
            Read-Host
        }
    }

    if ($Global:MakeReport) {
        Write-Host "``r✅ AKS Best Practices Check Completed." -ForegroundColor Green
    }
}
