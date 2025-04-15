function Invoke-CustomKubectlChecks {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    # Configuration
    $checksFolder = "$PSScriptRoot/yamlChecks"
    $kubectl = "kubectl"

    # Ensure required modules
    try {
        Import-Module powershell-yaml -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Failed to load powershell-yaml module: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Failed to load powershell-yaml module.</strong></p>" }
        if ($Json) { return @{ Error = "Failed to load powershell-yaml module: $_" } }
        return
    }

    function Get-ValidProperties {
        param (
            [array]$Items
        )
        $properties = @("Namespace", "Resource", "Value", "Message")
        $validProps = @()
    
        foreach ($prop in $properties) {
            $hasData = $false
            foreach ($item in $Items) {
                $value = $item.$prop
                if ($value -ne $null -and $value -ne "" -and $value -ne "-") {
                    $hasData = $true
                    break
                }
            }
            if ($hasData) {
                $validProps += $prop
            }
        }
        return $validProps
    }

    # Header
    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🛠️ Custom kubectl Checks]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Scanning for custom checks..." -ForegroundColor Yellow
    }

    # Fetch thresholds (if needed)
    $thresholds = if ($Global:MakeReport -or $Html -or $Json) {
        Get-KubeBuddyThresholds -Silent
    }
    else {
        Get-KubeBuddyThresholds
    }

    # Scan for YAML files
    try {
        if (-not (Test-Path $checksFolder)) {
            Write-Host "`r🤖 ⚠️ Checks folder $checksFolder does not exist." -ForegroundColor Yellow
            if ($Html) { return "<p><strong>⚠️ Checks folder does not exist.</strong></p>" }
            if ($Json) { return @{ Total = 0; Items = @() } }
            return
        }
        $checkFiles = Get-ChildItem -Path $checksFolder -Filter "*.yaml" -ErrorAction Stop
    }
    catch {
        Write-Host "`r🤖 ❌ Error scanning ${checksFolder}: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error scanning checks folder.</strong></p>" }
        if ($Json) { return @{ Error = "Error scanning checks folder: $_" } }
        return
    }

    if (-not $checkFiles) {
        Write-Host "`r🤖 ✅ No custom check YAML files found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No custom checks found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # Process checks
    $allResults = @()
    foreach ($file in $checkFiles) {
        try {
            $yamlContent = Get-Content $file.FullName -Raw | ConvertFrom-Yaml
            if (-not $yamlContent.checks) {
                Write-Host "`r🤖 ⚠️ No checks defined in $($file.Name)." -ForegroundColor Yellow
                continue
            }

            foreach ($check in $yamlContent.checks) {
                Write-Host "`r🤖 Processing check: $($check.ID) - $($check.Name)" -ForegroundColor Cyan

                # Custom script block execution (overrides default condition/operator logic)
                if ($check.Script) {
                    try {
                        $scriptBlock = [scriptblock]::Create($check.Script)
                        $customItems = & $scriptBlock -KubeData $KubeData -Namespace $Namespace
                
                        $checkResult = @{
                            ID             = $check.ID
                            Name           = $check.Name
                            Category       = $check.Category
                            Section        = $check.Section
                            ResourceKind   = $check.ResourceKind
                            Severity       = $check.Severity
                            Description    = $check.Description
                            Recommendation = if ($Html) {
                                if ($check.Recommendation -is [hashtable] -and $check.Recommendation.html) {
                                    $recContent = $check.Recommendation.html
                                    @"
<div class="recommendation-card">
  <details style='margin-bottom: 10px;'>
    <summary style='color: #0071FF; font-weight: bold; font-size: 14px; padding: 10px; background: #E3F2FD; border-radius: 4px 4px 0 0;'>Recommendations</summary>
    $recContent
  </details>
</div>
<div style='height: 15px;'></div>
"@
                                }
                                else {
                                    $check.Recommendation
                                }
                            }
                            elseif ($Json -or $Global:MakeReport) {
                                if ($check.Recommendation -is [hashtable] -and $check.Recommendation.text) {
                                    $check.Recommendation.text
                                }
                                else {
                                    $check.Recommendation
                                }
                            }
                            else {
                                $check.Recommendation
                            }
                            URL            = $check.URL
                            Items          = @()
                            Total          = 0
                        }
                
                        if ($customItems) {
                            $checkResult.Items = $customItems
                            $checkResult.Total = $customItems.Count
                        }
                
                        if ($checkResult.Total -eq 0) {
                            $checkResult.Message = "No issues detected for $($check.Name)."
                        }
                
                        $allResults += $checkResult
                    }
                    catch {
                        Write-Host "❌ Error executing script for $($check.ID): $_" -ForegroundColor Red
                        $allResults += @{
                            ID    = $check.ID
                            Name  = $check.Name
                            Error = "Script block execution failed: $_"
                        }
                    }
                    continue
                }                

                # Fetch data
                $data = $null
                if ($KubeData -and $KubeData.($check.ResourceKind)) {
                    $data = $KubeData.($check.ResourceKind).items
                }
                else {
                    $kubectlCmd = if ($Namespace) {
                        "$kubectl get $($check.ResourceKind) -n $Namespace -o json"
                    }
                    else {
                        "$kubectl get $($check.ResourceKind) --all-namespaces -o json"
                    }
                    try {
                        $output = Invoke-Expression $kubectlCmd 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            throw "kubectl failed: $output"
                        }
                        $data = ($output | ConvertFrom-Json).items
                    }
                    catch {
                        Write-Host "❌ Failed to fetch $($check.ResourceKind) data: $_" -ForegroundColor Red
                        $allResults += @{
                            ID    = $check.ID
                            Name  = $check.Name
                            Error = "Failed to fetch data: $_"
                        }
                        continue
                    }
                }

                if (-not $data) {
                    Write-Host "❌ No $($check.ResourceKind) data available." -ForegroundColor Red
                    if ($Html) { $allResults += @{ ID = $check.ID; Name = $check.Name; Message = "No $($check.ResourceKind) data available." } }
                    if ($Json) { $allResults += @{ ID = $check.ID; Name = $check.Name; Message = "No $($check.ResourceKind) data available." } }
                    continue
                }

                # Apply namespace filter
                if ($Namespace -and $data[0].metadata.PSObject.Properties.Name -contains 'namespace') {
                    $data = $data | Where-Object { $_.metadata.namespace -eq $Namespace }
                }                

                # Exclude namespaces if specified
                if ($ExcludeNamespaces) {
                    $data = Exclude-Namespaces -items $data
                }

                # Evaluate check
                $checkResult = @{
                    ID             = $check.ID
                    Name           = $check.Name
                    Category       = $check.Category
                    Section        = $check.Section
                    ResourceKind   = $check.ResourceKind
                    Severity       = $check.Severity
                    Description    = $check.Description
                    Recommendation = if ($Html) {
                        if ($check.Recommendation -is [hashtable] -and $check.Recommendation.html) {
                            $recContent = $check.Recommendation.html
                            @"
<div class="recommendation-card">
  <details style='margin-bottom: 10px;'>
    <summary style='color: #0071FF; font-weight: bold; font-size: 14px; padding: 10px; background: #E3F2FD; border-radius: 4px 4px 0 0;'>Recommendations</summary>
    $recContent
  </details>
</div>
<div style='height: 15px;'></div>
"@
                        }
                        else {
                            $check.Recommendation
                        }
                    }
                    elseif ($Json -or $Global:MakeReport) {
                        if ($check.Recommendation -is [hashtable] -and $check.Recommendation.text) {
                            $check.Recommendation.text
                        }
                        else {
                            $check.Recommendation
                        }
                    }
                    else {
                        $check.Recommendation
                    }                    
                    URL            = $check.URL
                    Items          = @()
                    Total          = 0
                }                

                # Validate required fields before processing each item
                if (-not $check.ID -or -not $check.Name -or -not $check.ResourceKind -or -not $check.Condition -or -not $check.Operator) {
                    Write-Host "⚠️ Skipping invalid check: missing required field(s)." -ForegroundColor Yellow
                    continue
                }
                $validOperators = @("not_contains", "contains", "equals", "not_equals", "greater_than", "less_than", "exists", "not_exists", "starts_with", "ends_with")
                if ($check.Operator -notin $validOperators) {
                    Write-Host "❌ Skipping check $($check.ID): unsupported operator '$($check.Operator)'" -ForegroundColor Red
                    continue
                }

                foreach ($item in $data) {
                    try {
                        $value = $item
                        foreach ($part in $check.Condition.Split('.')) {
                            if ($part -match '\[\]$') {
                                $field = $part -replace '\[\]$', ''
                                $value = $value.$field
                                if ($value -isnot [System.Array]) { $value = @($value) }
                            }
                            else {
                                $value = $value.$part
                            }
                            if ($null -eq $value) { break }
                        }
                
                        $failed = $false
                        switch ($check.Operator) {
                            "equals" {
                                $failed = $value -ne $check.Expected
                            }
                            "not_equals" {
                                $failed = $value -eq $check.Expected
                            }
                            "contains" {
                                $failed = -not ($value -like "*$($check.Expected)*")
                            }
                            "not_contains" {
                                $failed = ($value -like "*$($check.Expected)*")
                            }
                            "greater_than" {
                                $numeric = ($value | Measure-Object -Sum).Sum
                                $failed = $numeric -le $check.Expected
                            }
                            "less_than" {
                                $numeric = ($value | Measure-Object -Sum).Sum
                                $failed = $numeric -ge $check.Expected
                            }
                            "regex" {
                                $failed = -not ($value -match $check.Expected)
                            }
                            "is_null" {
                                $failed = $null -ne $value
                            }
                            "is_not_null" {
                                $failed = $null -eq $value
                            }
                            default {
                                Write-Host "❌ Unsupported operator: $($check.Operator)" -ForegroundColor Red
                                continue
                            }
                        }
                
                        if ($failed) {
                            $flattened = if ($value -is [System.Array]) { $value -join ', ' } else { $value }
                            $checkResult.Items += [PSCustomObject]@{
                                Namespace = if ($item.metadata.PSObject.Properties.Name -contains 'namespace') {
                                    $item.metadata.namespace
                                }
                                else {
                                    "(cluster)"
                                }
                                Resource  = "$($check.ResourceKind.ToLower())/$($item.metadata.name)"
                                Value     = $flattened
                                Message   = $check.FailMessage
                            }
                        }
                    }
                    catch {
                        Write-Host "❌ Error evaluating condition for $($item.metadata.name): $_" -ForegroundColor Red
                    }
                }                

                $checkResult.Total = $checkResult.Items.Count
                if ($checkResult.Total -eq 0) {
                    $checkResult.Message = "No issues detected for $($check.Name)."
                }
                $allResults += $checkResult
            }
        }
        catch {
            Write-Host "❌ Error processing $($file.Name): $_" -ForegroundColor Red
            if ($Html) { $allResults += @{ ID = "Unknown"; Name = $file.Name; Message = "Error processing file: $_" } }
            if ($Json) { $allResults += @{ ID = "Unknown"; Name = $file.Name; Message = "Error processing file: $_" } }
        }
    }

    # Generate reports
    if ($Json) {
        return @{ Total = ($allResults | Measure-Object -Sum -Property Total).Sum; Items = $allResults }
    }

    if ($Html) {
        $sectionGroups = @{}
        $collapsibleSectionMap = @{}
    
        foreach ($result in $allResults) {
            $section = if ($result.Section) { $result.Section } elseif ($result.Category) { $result.Category } else { "Other" }
            if (-not $sectionGroups.ContainsKey($section)) {
                $sectionGroups[$section] = @()
            }
            $sectionGroups[$section] += $result
        }
    
        foreach ($section in $sectionGroups.Keys) {
            $sectionHtml = ""
    
            foreach ($check in $sectionGroups[$section]) {
                # Tooltip (if Description present)
                $tooltip = if ($check.Description) {
                    "<span class='tooltip'><span class='info-icon'>i</span><span class='tooltip-text'>$($check.Description)</span></span>"
                }
                else { "" }
    
                # Header with tooltip
                $header = "<h2 id='$($check.ID)'>$($check.ID) - $($check.Name) $tooltip</h2>"
    
                # Summary line
                $summary = if ($check.Total -gt 0) {
                    "<p>⚠️ Total $($check.ResourceKind)s: $($check.Total)</p>"
                }
                else {
                    "<p>✅ No issues detected for this check.</p>"
                }
    
                # Recommendation (already HTML)
                $recommendationHtml = if ($check.Recommendation) { $check.Recommendation } else { "" }
    
                # Findings table (if any)
                $tableContent = if ($check.Items.Count -gt 0) {
                    $validProps = Get-ValidProperties -Items $check.Items
                    if ($validProps) {
                        $check.Items | ConvertTo-Html -Fragment -Property $validProps | Out-String
                    }
                    else {
                        "<p>No valid data to display.</p>"
                    }
                }
                else { "" }
    
                # Append to section HTML
                $sectionHtml += @"
<h2 id='$($check.ID)'>$($check.ID) - $($check.Name) $tooltip</h2>
$summary
"@

                if ($check.Items.Count -gt 0) {
                    $collapsibleContent = "$recommendationHtml`n$tableContent"
                    $sectionHtml += @"
<div class='table-container'>
  $(ConvertToCollapsible -Id $check.ID -defaultText "Show Findings" -content $collapsibleContent)
</div>
"@
                }

            }
    
            if ($collapsibleSectionMap.ContainsKey($section)) {
                $collapsibleSectionMap[$section] += "`n<div class='table-container'>$sectionHtml</div>"
            }
            else {
                $collapsibleSectionMap[$section] = "<div class='table-container'>$sectionHtml</div>"
            }
        }
    
        $checkStatusList = @()
        foreach ($section in $sectionGroups.Keys) {
            foreach ($check in $sectionGroups[$section]) {
                $status = if ($check.Total -eq 0) { 'Passed' } else { 'Failed' }
                $checkStatusList += [pscustomobject]@{
                    Id     = $check.ID
                    Status = $status
                }
            }
        }
                    
        return @{
            HtmlBySection = $collapsibleSectionMap
            StatusList    = $checkStatusList
        }
                    
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🛠️ Custom kubectl Checks]"
        foreach ($result in $allResults) {
            Write-ToReport "`n$($result.ID) - $($result.Name)"
            Write-ToReport "⚠️ Total Issues: $($result.Total)"
            if ($result.Items) {
                $validProps = Get-ValidProperties -Items $result.Items
                if ($validProps) {
                    $tableString = $result.Items | Format-Table -Property $validProps -AutoSize | Out-String
                    Write-ToReport $tableString
                }
                else {
                    Write-ToReport "No valid data to display."
                }
            }
            else {
                Write-ToReport "✅ $($result.Message)"
            }
            Write-ToReport "Category: $($result.Category)"
            Write-ToReport "Severity: $($result.Severity)"
            Write-ToReport "Recommendation: $($result.Recommendation)"
            Write-ToReport "URL: $($result.URL)"
        }
        return
    }

    # Console output
    Write-Host "`r🤖 ✅ Custom checks completed. ($($allResults.Count) checks processed)" -ForegroundColor Green
    foreach ($result in $allResults) {
        Write-Host "`n$($result.ID) - $($result.Name)" -ForegroundColor Cyan
        Write-Host "Total Issues: $($result.Total)" -ForegroundColor Yellow
        if ($result.Items) {
            $validProps = Get-ValidProperties -Items $result.Items
            if ($validProps) {
                $result.Items | Format-Table -Property $validProps -AutoSize | Out-Host
            }
            else {
                Write-Host "No valid data to display." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "✅ $($result.Message)" -ForegroundColor Green
        }
        Write-Host "Category: $($result.Category)" -ForegroundColor White
        Write-Host "Severity: $($result.Severity)" -ForegroundColor White
        Write-Host "Recommendation: $($result.Recommendation)" -ForegroundColor White
        if ($result.URL) {
            Write-Host "URL: $($result.URL)" -ForegroundColor Blue
        }
    }

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
        Read-Host "🤖 Press Enter to return to the menu"
    }
}