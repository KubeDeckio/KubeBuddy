function Invoke-EKSBestPractices {
    param (
        [string]$Region,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [switch]$Json,
        [switch]$Text,
        [object]$KubeData
    )

    function Validate-Context {
        param ($Region, $ClusterName)
        if ($KubeData) { return $true }
        $currentContext = kubectl config current-context 2>$null
        $eksContext = "arn:aws:eks:$($Region):*:cluster/$ClusterName"
        if ($currentContext -notlike "*$ClusterName*") {
            Write-Host "🔄 Setting kubectl context for EKS..." -ForegroundColor Yellow
            try {
                aws eks update-kubeconfig --region $Region --name $ClusterName
            } catch {
                Write-Host "❌ Failed to set EKS context." -ForegroundColor Red
                throw
            }
        }
        # Validate
        $nsCheck = kubectl get ns -o name 2>&1
        if ($nsCheck -match "error" -or $nsCheck -match "authorization") {
            Write-Host "❌ Auth error with kubectl." -ForegroundColor Red
            throw "kubectl context/auth failed."
        }
        Write-Host "✅ Context verified: $ClusterName" -ForegroundColor Green
        return $true
    }

    function Get-EKSClusterInfo {
        param (
            [string]$Region,
            [string]$ClusterName,
            [object]$KubeData
        )
        Write-Host -NoNewline "`n🤖 Fetching EKS cluster details..." -ForegroundColor Cyan
        $clusterInfo = $null
        $constraints = @()
        try {
            if ($KubeData -and $KubeData.EksCluster) {
                $clusterInfo = $KubeData.EksCluster
                $constraints = if ($KubeData.Constraints) { $KubeData.Constraints } else { @() }
                Write-Host "`r🤖 Using cached EKS cluster data from Get-KubeData. " -ForegroundColor Green
            }
            else {
                # If no cached data, we need to fetch it - but this should be rare since
                # KubeData should be collected first via Get-KubeData
                Write-Host "`r🤖 No cached data found. Consider using Get-KubeData first for better performance." -ForegroundColor Yellow
                
                # Basic cluster info only - full data collection should happen in Get-KubeData
                $clusterInfo = Get-EKSCluster -Region $Region -Name $ClusterName | ConvertTo-Json | ConvertFrom-Json
                Write-Host "`r🤖 Basic cluster data fetched.     " -ForegroundColor Green
                
                # Enhance cluster info with additional data for comprehensive checks
                Write-Host -NoNewline "`n🤖 Fetching additional EKS data..." -ForegroundColor Cyan
                
                # Get node groups
                try {
                    $nodeGroups = aws eks list-nodegroups --cluster-name $ClusterName --region $Region --output json | ConvertFrom-Json
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "NodeGroups" -Value $nodeGroups.nodegroups
                } catch { 
                    Write-Warning "Failed to fetch node groups: $_"
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "NodeGroups" -Value @()
                }
                
                # Get addons
                try {
                    $addons = aws eks list-addons --cluster-name $ClusterName --region $Region --output json | ConvertFrom-Json
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "Addons" -Value $addons.addons
                } catch { 
                    Write-Warning "Failed to fetch addons: $_"
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "Addons" -Value @()
                }
                
                # Get CloudTrail status (for security checks)
                try {
                    $trails = aws cloudtrail describe-trails --region $Region --output json | ConvertFrom-Json
                    $activeTrails = $trails.trailList | Where-Object { $_.IsLogging -eq $true }
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "CloudTrailEnabled" -Value ($activeTrails.Count -gt 0)
                } catch {
                    Write-Warning "Failed to fetch CloudTrail status: $_"
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "CloudTrailEnabled" -Value $false
                }
                
                # Get subnet details (for networking checks)
                try {
                    if ($clusterInfo.ResourcesVpcConfig.SubnetIds) {
                        $subnetDetails = @{}
                        foreach ($subnetId in $clusterInfo.ResourcesVpcConfig.SubnetIds) {
                            $subnet = aws ec2 describe-subnets --subnet-ids $subnetId --region $Region --output json | ConvertFrom-Json
                            if ($subnet.Subnets) {
                                $subnetDetails[$subnetId] = $subnet.Subnets[0]
                            }
                        }
                        $clusterInfo | Add-Member -MemberType NoteProperty -Name "SubnetDetails" -Value $subnetDetails
                    }
                } catch {
                    Write-Warning "Failed to fetch subnet details: $_"
                    $clusterInfo | Add-Member -MemberType NoteProperty -Name "SubnetDetails" -Value @{}
                }
                
                Write-Host -NoNewline "`n🤖 Fetching Kubernetes constraints..." -ForegroundColor Cyan
                $constraints = kubectl get constraints -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
                Write-Host "`r🤖 Enhanced EKS data fetched." -ForegroundColor Green
            }
            $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }
            return $clusterInfo
        }
        catch {
            Write-Host "`r❌ Error retrieving EKS or constraint data: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }

    # Load EKS check files from checks/
    $checksFolder = Join-Path -Path $PSScriptRoot -ChildPath "checks/"
    $checks = @()
    if (Test-Path $checksFolder) {
        $checkFiles = Get-ChildItem -Path $checksFolder -Filter "*.ps1" -ErrorAction SilentlyContinue
        foreach ($file in $checkFiles) {
            try { . $file.FullName } catch { Write-Warning "Failed to load $($file.Name): $_" }
        }
        Get-Variable -Name "*Checks" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Value -is [array]) { $checks += $_.Value }
        }
        $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }
    } else {
        Write-Warning "No EKS checks folder found at $checksFolder."
        $checks = @()
    }
    if ($checks.Count -eq 0) {
        Write-Warning "No EKS checks loaded. Using empty check set."
        $checks = @()
    }

    # Helper function to run all EKS checks
    function Run-Checks {
        param($clusterInfo)
        
        $allResults = @()
        $checkFiles = Get-ChildItem -Path "$PSScriptRoot/checks" -Filter "*.ps1"
        
        foreach ($checkFile in $checkFiles) {
            try {
                # Source the check file
                . $checkFile.FullName
                
                # Extract category name from filename (e.g., "SecurityChecks.ps1" -> "Security")
                $categoryName = $checkFile.BaseName -replace "Checks$", ""
                
                # Get the checks variable (e.g., $securityChecks)
                $checksVariableName = $checkFile.BaseName.ToLower()
                $checks = Get-Variable -Name $checksVariableName -ErrorAction SilentlyContinue
                
                if ($checks -and $checks.Value) {
                    $categoryResults = @()
                    
                    foreach ($check in $checks.Value) {
                        try {
                            # Execute the check's Value script block
                            $result = & $check.Value
                            $status = if ($result -eq $check.Expected) { "PASS" } else { "FAIL" }
                            
                            $categoryResults += @{
                                ID = $check.ID
                                Name = $check.Name
                                Status = $status
                                Message = $check.Name
                                FailMessage = if ($status -eq "FAIL") { $check.FailMessage } else { $null }
                                Recommendation = if ($status -eq "FAIL") { $check.Recommendation } else { $null }
                                Severity = $check.Severity
                                URL = $check.URL
                            }
                        }
                        catch {
                            Write-Warning "Error running check $($check.ID): $_"
                            $categoryResults += @{
                                ID = $check.ID
                                Name = $check.Name
                                Status = "ERROR"
                                Message = "Error: $_"
                                FailMessage = "Error executing check: $_"
                                Recommendation = "Check the implementation of this validation"
                                Severity = "Medium"
                            }
                        }
                    }
                    
                    $allResults += @{
                        Category = $categoryName
                        Results = $categoryResults
                    }
                }
            }
            catch {
                Write-Warning "Error loading check file $($checkFile.Name): $_"
            }
        }
        
        return $allResults
    }

    # Helper function to display results
    function Display-Results {
        param(
            $categories,
            [switch]$FailedOnly,
            [switch]$Json,
            [switch]$Html,
            [switch]$Text
        )
        
        if ($Json) {
            $jsonResults = @{
                Total = 0
                Passed = 0
                Failed = 0
                Categories = @()
                Items = @()  # Add Items for KubeBuddy compatibility
            }
            
            foreach ($category in $categories) {
                $categoryResults = @{
                    Name = $category.Category
                    Checks = @()
                }
                
                foreach ($check in $category.Results) {
                    if (-not $FailedOnly -or $check.Status -eq "FAIL") {
                        # Add to category
                        $categoryResults.Checks += $check
                        
                        # Add to Items for KubeBuddy main reporting
                        $jsonResults.Items += @{
                            ID = $check.ID
                            Name = $check.Name
                            Message = if ($check.Status -eq "FAIL") { $check.FailMessage } else { "Check passed" }
                            Status = $check.Status
                            Category = $category.Category
                            Severity = $check.Severity
                            Recommendation = $check.Recommendation
                            URL = $check.URL
                        }
                        
                        $jsonResults.Total++
                        if ($check.Status -eq "PASS") { $jsonResults.Passed++ }
                        else { $jsonResults.Failed++ }
                    }
                }
                
                if ($categoryResults.Checks.Count -gt 0) {
                    $jsonResults.Categories += $categoryResults
                }
            }
            
            return $jsonResults | ConvertTo-Json -Depth 10
        }
        elseif ($Html) {
            # Calculate statistics
            $totalChecks = ($categories | ForEach-Object { $_.Results }).Count
            $passedChecks = ($categories | ForEach-Object { $_.Results } | Where-Object { $_.Status -eq "PASS" }).Count
            $failedChecks = $totalChecks - $passedChecks
            $score = if ($totalChecks -eq 0) { 0 } else { [math]::Round(($passedChecks / $totalChecks) * 100, 2) }
            $rating = switch ($score) {
                { $_ -ge 90 } { "A" }
                { $_ -ge 80 } { "B" }
                { $_ -ge 70 } { "C" }
                { $_ -ge 60 } { "D" }
                default { "F" }
            }
            
            # Build HTML table for failed/error checks
            $htmlTable = if ($failedChecks -gt 0) {
                $failedResults = $categories | ForEach-Object { 
                    $category = $_.Category
                    $_.Results | Where-Object { $_.Status -ne "PASS" } | ForEach-Object { 
                        $_ | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -PassThru 
                    }
                }
                
                $htmlRows = $failedResults | ForEach-Object {
                    $id = $_.ID
                    $name = $_.Name
                    $severity = $_.Severity
                    $category = $_.Category
                    $status = if ($_.Status -eq "PASS") { "✅ PASS" } else { "❌ FAIL" }
                    $failMessage = $_.FailMessage
                    $recommendation = $_.Recommendation
                    $url = if ($_.URL) { "<a href='$($_.URL)' target='_blank'>Learn More</a>" } else { "" }
                    "<tr><td>$id</td><td>$name</td><td>$severity</td><td>$category</td><td>$status</td><td>$failMessage</td><td>$recommendation</td><td>$url</td></tr>"
                }
                "<table>`n<thead><tr><th>ID</th><th>Check</th><th>Severity</th><th>Category</th><th>Status</th><th>Fail Message</th><th>Recommendation</th><th>URL</th></tr></thead>`n<tbody>`n" + ($htmlRows -join "`n") + "`n</tbody>`n</table>"
            }
            else {
                "<p><strong>No best practice violations detected.</strong></p>"
            }
            
            return [PSCustomObject]@{
                Passed = $passedChecks
                Failed = $failedChecks
                Total  = $totalChecks
                Score  = $score
                Rating = "$rating"
                Data   = $htmlTable
            }
        }
        else {
            # Text output (default)
            foreach ($category in $categories) {
                Write-Host "`n🔍 $($category.Category) Checks:" -ForegroundColor Cyan
                Write-Host "=" * 40 -ForegroundColor DarkGray
                
                foreach ($check in $category.Results) {
                    if (-not $FailedOnly -or $check.Status -eq "FAIL") {
                        $status = if ($check.Status -eq "PASS") { "✅ PASS" } else { "❌ FAIL" }
                        Write-Host "📋 $($check.ID): $($check.Message) - $status" -ForegroundColor $(if ($check.Status -eq "PASS") { "Green" } else { "Red" })
                        
                        if ($check.Status -eq "FAIL" -and $check.Recommendation) {
                            Write-Host "   💡 Recommendation: $($check.Recommendation)" -ForegroundColor Yellow
                        }
                    }
                }
            }
            
            # Summary
            $totalChecks = ($categories | ForEach-Object { $_.Results }).Count
            $passedChecks = ($categories | ForEach-Object { $_.Results } | Where-Object { $_.Status -eq "PASS" }).Count
            $failedChecks = $totalChecks - $passedChecks
            
            Write-Host "`n📊 Summary:" -ForegroundColor Cyan
            Write-Host "   Total Checks: $totalChecks" -ForegroundColor White
            Write-Host "   Passed: $passedChecks" -ForegroundColor Green
            Write-Host "   Failed: $failedChecks" -ForegroundColor Red
            
            return @{
                Total = $totalChecks
                Passed = $passedChecks
                Failed = $failedChecks
            }
        }
    }

    # You can reuse your Run-Checks and Display-Results functions with minor tweaks if needed

    # Main Execution Flow
    if ($Text) { Write-Host -NoNewline "`n🤖 Starting EKS Best Practices Check...`n" -ForegroundColor Cyan }
    try {
        Validate-Context -Region $Region -ClusterName $ClusterName
        $clusterInfo = Get-EKSClusterInfo -Region $Region -ClusterName $ClusterName -KubeData $KubeData
        if (-not $clusterInfo) { throw "Failed to retrieve EKS cluster info." }
        $checkResults = Run-Checks -clusterInfo $clusterInfo
        if ($Json) { return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Json }
        elseif ($Html) { return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html }
        elseif ($Text) { $results = Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Text; return $results }
        else { Display-Results -categories $checkResults -FailedOnly:$FailedOnly }
    }
    catch {
        Write-Error "❌ Error running EKS Best Practices: $_"
        if ($Json) {
            return @{
                Total = 0
                Items = @(@{
                        ID      = "EKSBestPractices"
                        Name    = "EKS Best Practices"
                        Message = "Error running EKS checks: $_"
                        Total   = 0
                        Items   = @()
                    })
            }
        }
        throw
    }
    if ($Text) { Write-Host "`r✅ EKS Best Practices Check Completed." -ForegroundColor Green }
}