function Invoke-AKSBestPractices {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [switch]$Json,
        [switch]$Text,
        [object]$KubeData
    )

    function Validate-Context {
        param ($ResourceGroup, $ClusterName)
    
        if ($KubeData) { return $true }
    
        $currentContext = kubectl config current-context 2>$null
        $aksContext = $null
    
        try {
            $aksContext = az aks show --resource-group $ResourceGroup --name $ClusterName --query "name" -o tsv --only-show-errors 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $aksContext) {
                throw "Failed to retrieve AKS context."
            }
        }
        catch {
            Write-Error "❌ Error fetching AKS context: $_"
            throw "Critical error: Unable to continue without AKS context."
        }
    
        # If not already set to correct context, try to fix it
        if ($currentContext -ne $aksContext) {
            Write-Host "🔄 Attempting to set kubectl context using az aks get-credentials..." -ForegroundColor Yellow
            try {
                az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing --only-show-errors
                $currentContext = kubectl config current-context
            }
            catch {
                Write-Host "❌ Failed to set kubectl context automatically." -ForegroundColor Red
                throw
            }
        }
    
        # Try a kubectl command to validate credentials
        $nsCheck = kubectl get ns -o name 2>&1
        if ($nsCheck -match "To sign in" -or $nsCheck -match "authorization") {
            Write-Host "❗ Detected token/auth error with kubectl. Attempting non-interactive fix..." -ForegroundColor Yellow
    
            if (Get-Command kubelogin -ErrorAction SilentlyContinue) {
                try {
                    $spnProvided = $env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID
                    if ($spnProvided) {
                        kubelogin convert-kubeconfig -l spn `
                            --client-id $env:AZURE_CLIENT_ID `
                            --client-secret $env:AZURE_CLIENT_SECRET `
                            --tenant-id $env:AZURE_TENANT_ID
                    } else {
                        kubelogin convert-kubeconfig -l azurecli
                    }
                    Write-Host "✅ kubelogin applied successfully." -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ kubelogin failed: $_" -ForegroundColor Red
                    throw
                }
            }
            else {
                Write-Host "❌ kubelogin not installed and cluster auth failed." -ForegroundColor Red
                throw "kubelogin required to fix non-interactive auth issue."
            }
        }
    
        # Final validation
        if ($currentContext -eq $aksContext) {
            Write-Host "✅ Context verified: $currentContext" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ WARNING: Context mismatch. Expected: $aksContext, Got: $currentContext" -ForegroundColor Red
            return $false
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
            }
            else {
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
    
            $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }
    
            return $clusterInfo
        }
        catch {
            Write-Host "`r❌ Error retrieving AKS or constraint data: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }

    # Load AKS check files from checks/
    $checksFolder = Join-Path -Path $PSScriptRoot -ChildPath "checks/"
    $checks = @()
    if (Test-Path $checksFolder) {
        $checkFiles = Get-ChildItem -Path $checksFolder -Filter "*.ps1" -ErrorAction SilentlyContinue
        foreach ($file in $checkFiles) {
            try {
                # Dot-source the file to define *Checks variables
                . $file.FullName
            }
            catch {
                Write-Warning "Failed to load $($file.Name): $_"
            }
        }
        # Collect all *Checks variables
        Get-Variable -Name "*Checks" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Value -is [array]) {
                foreach ($check in $_.Value) {
                    # Validate required fields
                    if (-not $check.ID) { $check.ID = "UNKNOWN_$($checks.Count + 1)" }
                    if (-not $check.Name) { $check.Name = "Unnamed Check $($check.ID)" }
                    if (-not $check.Category) { $check.Category = "Unknown" }
                    if (-not $check.Severity) { $check.Severity = "Medium" }
                    if (-not $check.FailMessage) { $check.FailMessage = "Check failed." }
                    if (-not $check.Recommendation) { $check.Recommendation = $check.FailMessage }
                    $checks += $check
                }
            }
        }
        $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }
    }
    else {
        Write-Warning "No AKS checks folder found at $checksFolder."
        $checks = @()
    }

    # Fallback if no checks are loaded
    if ($checks.Count -eq 0) {
        Write-Warning "No AKS checks loaded. Using empty check set."
        $checks = @()
    }

    function Run-Checks {
        param ($clusterInfo)
        if (-not $Html -and -not $Json -and -not $Text) {
            Write-Host -NoNewline "`n🤖 Running best practice checks..." -ForegroundColor Cyan
        }

        $categories = @{
            "Security"             = @()
            "Networking"           = @()
            "Resource Management"  = @()
            "Monitoring & Logging" = @()
            "Identity & Access"    = @()
            "Disaster Recovery"    = @()
            "Best Practices"       = @()
        }

        if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }

        $checkResults = @()
        $thresholds = Get-KubeBuddyThresholds -Silent
        $excludedCheckIDs = $thresholds.excluded_checks

        foreach ($check in $checks) {
            try {
                if ($excludedCheckIDs -contains $check.ID) {
                    Write-Host "⏭️  Skipping excluded AKS check: $($check.ID)" -ForegroundColor DarkGray
                    continue
                }                
                # Evaluate Value scriptblock
                $value = if ($check.Value -is [scriptblock]) {
                    $vars = [System.Collections.Generic.List[System.Management.Automation.PSVariable]]::new()
                    $vars.Add([System.Management.Automation.PSVariable]::new('clusterInfo', $clusterInfo))
                    $check.Value.InvokeWithContext($null, $vars)
                }
                elseif ($check.Value -match "^(True|False|[0-9]+)$") {
                    [bool]([System.Convert]::ChangeType($check.Value, [boolean]))
                }
                else {
                    Invoke-Expression ($check.Value -replace '\$clusterInfo', '$clusterInfo')
                }

                # Evaluate Expected scriptblock or value
                $expected = if ($check.Expected -is [scriptblock]) {
                    & $check.Expected $value
                }
                else {
                    $check.Expected
                }

                $result = if ($value -eq $expected) { "✅ PASS" } else { "❌ FAIL" }
        
                $failMsg = ""
                if ($result -eq "❌ FAIL") {
                    $failMsg = if ($check.FailMessage -is [scriptblock]) {
                        & $check.FailMessage $value
                    }
                    else {
                        $check.FailMessage
                    }
                }
                
                $checkResult = [PSCustomObject]@{
                    ID             = $check.ID
                    Name           = $check.Name
                    Severity       = $check.Severity
                    Category       = $check.Category
                    Status         = $result
                    FailMessage    = $failMsg
                    Recommendation = if ($result -eq "✅ PASS") { "$($check.Name) is enabled." } else { $check.Recommendation }
                    URL            = $check.URL
                    Items          = if ($result -eq "❌ FAIL") { @(@{ Resource = $check.Name; Issue = $failMsg }) } else { @() }
                    Total          = if ($result -eq "❌ FAIL") { 1 } else { 0 }
                }                

                $categories[$check.Category] += $checkResult
                $checkResults += $checkResult

            }
            catch {
                Write-Host "Error processing check $($check.ID): $_" -ForegroundColor Red
                $checkResult = [PSCustomObject]@{
                    ID             = $check.ID
                    Name           = $check.Name ? $check.Name : "Unnamed Check $($check.ID)"
                    Severity       = $check.Severity ? $check.Severity : "Medium"
                    Category       = $check.Category ? $check.Category : "Unknown"
                    Status         = "❌ ERROR"
                    Recommendation = "Error processing check: $_"
                    URL            = $check.URL
                    Items          = @(@{ Resource = $check.Name ? $check.Name : $check.ID; Issue = "Error: $_" })
                    Total          = 1
                }
                $categories[$check.Category] += $checkResult
                $checkResults += $checkResult
            }
        }

        if ($Json) {
            return @{
                Total = ($checkResults | Measure-Object -Sum Total).Sum
                Items = $checkResults
            }
        }
        return $categories
    }

    function Display-Results {
        param (
            [hashtable]$categories,
            [switch]$FailedOnly,
            [switch]$Html,
            [switch]$Json
        )
    
        $passCount = 0
        $failCount = 0
        $reportData = @()
    
        foreach ($category in $categories.Keys) {
            $checks = $categories[$category]
            if ($FailedOnly) {
                $checks = $checks | Where-Object { $_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR" }
            }
    
            if ($checks.Count -gt 0 -and -not $Html -and -not $Json -and -not $Text) {
                Write-Host "`n=== $category ===             " -ForegroundColor Cyan              
                $checks | Format-Table ID, Check, Severity, Category, Status, Recommendation, @{Label = "URL"; Expression = { $_."URL" } } -AutoSize | Out-String | Write-Host
    
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
    
            $reportData += $checks | Select-Object ID, @{Name = "Check"; Expression = { $_.Name } }, Severity, Category, Status, FailMessage, Recommendation, @{
                Name       = 'URL'
                Expression = { if ($_.URL) { "<a href='$($_.URL)' target='_blank'>Learn More</a>" } else { "" } }
            }
    
            $passCount += ($checks | Where-Object { $_.Status -eq "✅ PASS" }).Count
            $failCount += ($checks | Where-Object { $_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR" }).Count
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
    
        if (-not $Html -and -not $Json -and -not $Text) {
            Write-Host "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-Host $header -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Cyan
            Write-Host "$row " -NoNewline
            Write-Host "$rating" -ForegroundColor $ratingColor
        }
    
        if ($Text) {
            $textOutput = @()
            $textOutput += "`nSummary & Rating:           "
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
            $textOutput += $header
            $textOutput += $separator
            $textOutput += "$row $rating"
    
            # Return the results as an object for the caller to handle
            return [PSCustomObject]@{
                Passed     = $passCount
                Failed     = $failCount
                Total      = $total
                Score      = $score
                Rating     = $rating
                Items      = $reportData | ForEach-Object {
                    [PSCustomObject]@{
                        ID             = $_.ID
                        Name           = $_.Check
                        Severity       = $_.Severity
                        Category       = $_.Category
                        Status         = $_.Status
                        FailMessage    = $_.FailMessage
                        Recommendation = $_.Recommendation
                        URL            = $_.URL -replace '<a href=''([^'']+)'' target=''_blank''>Learn More</a>', '$1'
                        Total          = if ($_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR") { 1 } else { 0 }
                        Items          = if ($_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR") {
                            @(@{
                                    Resource = $_.Check
                                    Issue    = $_.FailMessage
                                })
                        }
                        else {
                            @()
                        }
                    }
                }
                TextOutput = $textOutput
            }
        }
    
        if ($Html) {
            $htmlTable = if ($reportData.Count -gt 0) {
                $sortedReportData = $reportData | Sort-Object @{Expression = { $_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR" }; Descending = $true }, Category
                $htmlRows = $sortedReportData | ForEach-Object {
                    $id = $_.ID
                    $check = $_.Check
                    $severity = $_.Severity
                    $category = $_.Category
                    $status = $_.Status
                    $failMessage = $_.FailMessage
                    $recommendation = $_.Recommendation
                    $url = $_.URL
                    "<tr><td>$id</td><td>$check</td><td>$severity</td><td>$category</td><td>$status</td><td>$failMessage</td><td>$recommendation</td><td>$url</td></tr>"
                }
                "<table>`n<thead><tr><th>ID</th><th>Check</th><th>Severity</th><th>Category</th><th>Status</th><th>Fail Message</th><th>Recommendation</th><th>URL</th></tr></thead>`n<tbody>`n" + ($htmlRows -join "`n") + "`n</tbody>`n</table>"
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
    
        if ($Json) {
            return @{
                Total = $total
                Items = $reportData | ForEach-Object {
                    @{
                        ID             = $_.ID
                        Name           = $_.Check
                        Severity       = $_.Severity
                        Category       = $_.Category
                        Status         = $_.Status
                        FailMessage    = $_.FailMessage
                        Recommendation = $_.Recommendation
                        URL            = $_.URL -replace '<a href=''([^'']+)'' target=''_blank''>Learn More</a>', '$1'
                        Items          = if ($_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR") { @(@{ Resource = $_.Check; Issue = $_.Recommendation }) } else { @() }
                        Total          = if ($_.Status -eq "❌ FAIL" -or $_.Status -eq "❌ ERROR") { 1 } else { 0 }
                    }
                }
            }
        }
    }

    # Main Execution Flow
    if ($Text) {
        Write-Host -NoNewline "`n🤖 Starting AKS Best Practices Check...`n" -ForegroundColor Cyan
    }

    try {
        Validate-Context -ResourceGroup $ResourceGroup -ClusterName $ClusterName
        $clusterInfo = Get-AKSClusterInfo -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData $KubeData
        if (-not $clusterInfo) {
            throw "Failed to retrieve AKS cluster info."
        }

        $checkResults = Run-Checks -clusterInfo $clusterInfo

        if ($Json) {
            return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Json
        }
        elseif ($Html) {
            return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html
        }
        elseif ($Text) {
            $results = Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Text
            return $results  # Return the results for the caller to handle
        }
        else {
            Display-Results -categories $checkResults -FailedOnly:$FailedOnly
            if (-not $Text) {
                Write-Host "`nPress Enter to return to the menu..." -ForegroundColor Yellow
                Read-Host
            }
        }
    }
    catch {
        Write-Error "❌ Error running AKS Best Practices: $_"
        if ($Json) {
            return @{
                Total = 0
                Items = @(@{
                        ID      = "AKSBestPractices"
                        Name    = "AKS Best Practices"
                        Message = "Error running AKS checks: $_"
                        Total   = 0
                        Items   = @()
                    })
            }
        }
        throw
    }

    if ($Text) {
        Write-Host "`r✅ AKS Best Practices Check Completed." -ForegroundColor Green
    }
}