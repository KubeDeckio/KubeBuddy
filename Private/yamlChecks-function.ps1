function Invoke-yamlChecks {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [switch]$Html,
        [switch]$Json,
        [switch]$Text,
        [switch]$ExcludeNamespaces,
        [string[]]$CheckIDs = @()  # Optional parameter to filter specific check IDs
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
            [array]$Items,
            [string]$CheckID
        )
    
        # Static table layouts for known checks
        $checkSpecificProperties = @{
            "NODE001" = @("Node", "Status", "Issues")
            "NODE002" = @("Node", "CPU Status", "CPU %", "CPU Used", "CPU Total", "Mem Status", "Mem %", "Mem Used", "Mem Total", "Disk %", "Disk Status")
        }
    
        if ($checkSpecificProperties.ContainsKey($CheckID)) {
            $properties = $checkSpecificProperties[$CheckID]
        }
        else {
            # Detect valid properties dynamically for unknown/script-based checks
            $properties = $Items |
            ForEach-Object { $_.PSObject.Properties.Name } |
            Group-Object |
            Sort-Object Count -Descending |
            Select-Object -ExpandProperty Name -Unique
        }
    
        $validProps = @()
        foreach ($prop in $properties) {
            $hasData = $Items | Where-Object {
                $_.$prop -ne $null -and $_.$prop -ne "" -and $_.$prop -ne "-"
            }
            if ($hasData.Count -gt 0) {
                $validProps += $prop
            }
        }
    
        # Fallback to static props if NODE check and nothing found
        if (-not $validProps -and $CheckID -in @("NODE001", "NODE002")) {
            $validProps = $checkSpecificProperties[$CheckID]
        }
    
        return $validProps
    }
    

    function Get-ResourceKindDisplayNames {
        param (
            [string]$ResourceKind
        )

        # Map of ResourceKind values to their singular and plural forms
        $resourceKindMap = @{
            "namespaces"              = @{ Singular = "Namespace"; Plural = "Namespaces" }
            "resourcequotas"          = @{ Singular = "ResourceQuota"; Plural = "ResourceQuotas" }
            "limitranges"             = @{ Singular = "LimitRange"; Plural = "LimitRanges" }
            "Service"                 = @{ Singular = "Service"; Plural = "Services" }
            "Ingress"                 = @{ Singular = "Ingress"; Plural = "Ingresses" }
            "ClusterRoleBinding"      = @{ Singular = "ClusterRoleBinding"; Plural = "ClusterRoleBindings" }
            "ServiceAccount"          = @{ Singular = "ServiceAccount"; Plural = "ServiceAccounts" }
            "Role, ClusterRole"       = @{ Singular = "Role/ClusterRole"; Plural = "Roles/ClusterRoles" }
            "Secret"                  = @{ Singular = "Secret"; Plural = "Secrets" }
            "Pod"                     = @{ Singular = "Pod"; Plural = "Pods" }
            "DaemonSet"               = @{ Singular = "DaemonSet"; Plural = "DaemonSets" }
            "Deployment"              = @{ Singular = "Deployment"; Plural = "Deployments" }
            "StatefulSet"             = @{ Singular = "StatefulSet"; Plural = "StatefulSets" }
            "HorizontalPodAutoscaler" = @{ Singular = "HorizontalPodAutoscaler"; Plural = "HorizontalPodAutoscalers" }
            "PersistentVolumeClaim"   = @{ Singular = "PersistentVolumeClaim"; Plural = "PersistentVolumeClaims" }
            "events"                  = @{ Singular = "Event"; Plural = "Events" }
            "jobs"                    = @{ Singular = "Job"; Plural = "Jobs" }
            "ConfigMap"               = @{ Singular = "ConfigMap"; Plural = "ConfigMaps" }
            "Node"                    = @{ Singular = "Node"; Plural = "Nodes" }
        }

        if ($resourceKindMap.ContainsKey($ResourceKind)) {
            return $resourceKindMap[$ResourceKind]
        }
        else {
            # Default: assume the ResourceKind is singular and append "s" for plural
            return @{
                Singular = $ResourceKind
                Plural   = "$ResourceKind" + "s"
            }
        }
    }

    # Fetch thresholds
    $thresholds = if ($Text -or $Html -or $Json) {
        Get-KubeBuddyThresholds -Silent
    }
    else {
        Get-KubeBuddyThresholds
    }

    # Scan for YAML files
    try {
        if (-not (Test-Path $checksFolder)) {
            Write-Host "⚠️ Checks folder $checksFolder does not exist." -ForegroundColor Yellow
            if ($Html) { return "<p><strong>⚠️ Checks folder does not exist.</strong></p>" }
            if ($Json) { return @{ Total = 0; Items = @() } }
            return
        }
        $checkFiles = Get-ChildItem -Path $checksFolder -Filter "*.yaml" -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Error scanning ${checksFolder}: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error scanning checks folder.</strong></p>" }
        if ($Json) { return @{ Error = "Error scanning checks folder: $_" } }
        return
    }

    if (-not $checkFiles) {
        Write-Host "✅ No custom check YAML files found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No custom checks found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        return
    }

    # Process checks
    $allResults = @()
    foreach ($file in $checkFiles) {
        try {
            $yamlContent = Get-Content $file.FullName -Raw | ConvertFrom-Yaml
            if (-not $yamlContent.checks) {
                continue
            }

            foreach ($check in $yamlContent.checks) {
                # Filter checks if CheckIDs specified
                if ($CheckIDs -and $check.ID -notin $CheckIDs) {
                    continue
                }

                Write-Host -NoNewline "🤖 Processing check: $($check.ID) - $($check.Name)..." -ForegroundColor Cyan

                # Custom script block execution
                if ($check.Script) {
                    try {
                        # Define disallowed kubectl commands (mutating operations)
                        $disallowedCommands = @(
                            "create",
                            "run",
                            "edit",
                            "delete",
                            "patch",
                            "apply",
                            "replace",
                            "scale",
                            "rollout",
                            "annotate",
                            "label",
                            "taint",
                            "cordon",
                            "uncordon",
                            "drain",
                            "evict"
                        )

                        # Check the script for disallowed commands
                        $scriptContent = $check.Script
                        $disallowedCommandFound = $false
                        $foundCommand = $null
                        foreach ($cmd in $disallowedCommands) {
                            $pattern = "(?i)\bkubectl\s+$cmd\b"
                            if ($scriptContent -match $pattern) {
                                $disallowedCommandFound = $true
                                $foundCommand = $cmd
                                break
                            }
                        }

                        if ($disallowedCommandFound) {
                            $errorMessage = "❌ Check $($check.ID) contains disallowed kubectl command '$foundCommand'. Scripts must not modify cluster state (e.g., create, delete, patch)."
                            Write-Host $errorMessage -ForegroundColor Red
                            $allResults += @{
                                ID    = $check.ID
                                Name  = $check.Name
                                Error = $errorMessage
                            }
                            continue
                        }

                        $scriptBlock = [scriptblock]::Create($check.Script)
                        # Pass thresholds to the script block for NODE002
                        $scriptResult = if ($check.ID -eq "NODE002") {
                            & $scriptBlock -KubeData $KubeData -Thresholds $thresholds
                        }
                        else {
                            & $scriptBlock -KubeData $KubeData
                        }

                        $checkResult = @{
                            ID             = $check.ID
                            Name           = $check.Name
                            Category       = $check.Category
                            Section        = $check.Section
                            ResourceKind   = $check.ResourceKind
                            Severity       = $check.Severity
                            Weight         = $check.Weight
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
                            else {
                                if ($check.Recommendation -is [hashtable] -and $check.Recommendation.text) {
                                    $check.Recommendation.text
                                }
                                else {
                                    $check.Recommendation
                                }
                            }
                            URL            = $check.URL
                            Items          = @()
                            Total          = 0
                        }

                        if ($scriptResult -is [hashtable] -and $scriptResult.Items) {
                            $checkResult.Items = $scriptResult.Items
                            $checkResult.Total = $scriptResult.IssueCount
                        }
                        elseif ($scriptResult) {
                            $checkResult.Items = $scriptResult
                            $checkResult.Total = $scriptResult.Count
                        }

                        if ($checkResult.Total -eq 0) {
                            $checkResult.Message = "No issues detected for $($check.Name)."
                        }

                        $allResults += $checkResult
                        Write-Host "`r✅ Completed check: $($check.ID) - $($check.Name)      " -ForegroundColor Green
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

                # Non-script check logic
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
                    $allResults += @{
                        ID      = $check.ID
                        Name    = $check.Name
                        Message = "No $($check.ResourceKind) data available."
                    }
                    continue
                }

                if ($Namespace -and $data[0].metadata.PSObject.Properties.Name -contains 'namespace') {
                    $data = $data | Where-Object { $_.metadata.namespace -eq $Namespace }
                }

                if ($ExcludeNamespaces) {
                    $data = Exclude-Namespaces -items $data
                }

                $checkResult = @{
                    ID             = $check.ID
                    Name           = $check.Name
                    Category       = $check.Category
                    Section        = $check.Section
                    ResourceKind   = $check.ResourceKind
                    Severity       = $check.Severity
                    Weight         = $check.Weight
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
                    else {
                        if ($check.Recommendation -is [hashtable] -and $check.Recommendation.text) {
                            $check.Recommendation.text
                        }
                        else {
                            $check.Recommendation
                        }
                    }
                    URL            = $check.URL
                    Items          = @()
                    Total          = 0
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
                            "equals" { $failed = $value -ne $check.Expected }
                            "not_equals" { $failed = $value -eq $check.Expected }
                            "contains" { $failed = -not ($value -like "*$($check.Expected)*") }
                            "not_contains" { $failed = ($value -like "*$($check.Expected)*") }
                            "greater_than" { $failed = ($value | Measure-Object -Sum).Sum -le $check.Expected }
                            "less_than" { $failed = ($value | Measure-Object -Sum).Sum -ge $check.Expected }
                            default { OCD Write-Host "❌ Unsupported operator: $($check.Operator)" -ForegroundColor Red; continue }
                        }

                        if ($failed) {
                            $flattened = if ($value -is [System.Array]) { $value -join ', ' } else { $value }
                            $checkResult.Items += [PSCustomObject]@{
                                Namespace = if ($item.metadata.PSObject.Properties.Name -contains 'namespace') { $item.metadata.namespace } else { "(cluster)" }
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
                Write-Host "`r✅ Completed check: $($check.ID) - $($check.Name)      " -ForegroundColor Green
            }
        }
        catch {
            Write-Host "❌ Error processing $($file.Name): $_" -ForegroundColor Red
            if ($Html) { $allResults += @{ ID = "Unknown"; Name = $file.Name; Message = "Error processing file: $_" } }
            if ($Json) { $allResults += @{ ID = "Unknown"; Name = $file.Name; Message = "Error processing file: $_" } }
        }
    }

    # HTML output
    if ($Html) {
        $sectionGroups = @{}
        $collapsibleSectionMap = @{}
        $targetCheckIDs = @("NODE001", "NODE002")  # Checks to show tables non-collapsed

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
                # Debug: Log the ResourceKind to confirm its value
                # Write-Host "DEBUG: Check ID: $($check.ID), ResourceKind: $($check.ResourceKind)" -ForegroundColor Yellow

                $tooltip = if ($check.Description) {
                    "<span class='tooltip'><span class='info-icon'>i</span><span class='tooltip-text'>$($check.Description)</span></span>"
                }
                else { "" }

                $header = "<h2 id='$($check.ID)'>$($check.ID) - $($check.Name) $tooltip</h2>"

                # Get the display names for the ResourceKind
                $resourceKind = $check.ResourceKind
                $displayNames = Get-ResourceKindDisplayNames -ResourceKind $resourceKind
                $resourceKindPlural = $displayNames.Plural

                $summary = if ($check.Total -gt 0) {
                    "<p>⚠️ Total $resourceKindPlural with Issues: $($check.Total)</p>"
                }
                else {
                    "<p>✅ All $resourceKindPlural are healthy.</p>"
                }

                $recommendationHtml = if ($check.Recommendation) { $check.Recommendation } else { "" }
                $tableContent = if ($check.Items) {
                    $validProps = Get-ValidProperties -Items $check.Items -CheckID $check.ID
                    if ($validProps) {
                        $check.Items | ConvertTo-Html -Fragment -Property $validProps | Out-String
                    }
                    else {
                        "<p>No valid data to display.</p>"
                    }
                }
                else {
                    ""
                }

                # For NODE001 and NODE002, show table non-collapsed; others use collapsible
                if ($check.ID -in $targetCheckIDs) {
                    $sectionHtml += @"
$header
$summary
<div class='table-container'>
  $recommendationHtml
  $tableContent
</div>
"@
                }
                else {
                    $collapsibleContent = "$recommendationHtml`n$tableContent"
                    $sectionHtml += @"
$header
$summary
"@
                    if ($check.Items) {
                        $sectionHtml += @"
<div class='table-container'>
  $(ConvertToCollapsible -Id $check.ID -defaultText "Show Findings" -content $collapsibleContent)
</div>
"@
                    }
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
        $checkScoreList = @()
        foreach ($section in $sectionGroups.Keys) {
            foreach ($check in $sectionGroups[$section]) {
                $status = if ($check.Total -eq 0) { 'Passed' } else { 'Failed' }
                $checkStatusList += [pscustomobject]@{
                    Id     = $check.ID
                    Status = $status
                    Weight = $check.Weight
                }
                $checkScoreList += [pscustomobject]@{
                    Id     = $check.ID
                    Weight = $check.Weight
                    Total  = if ($status -eq 'Passed') { 0 } else { 1 }
                }                
            }
        }

        return @{
            HtmlBySection = $collapsibleSectionMap
            StatusList    = $checkStatusList
            ScoreList     = $checkScoreList 
        }
    }

    # JSON output (unchanged)
    if ($Json) {
        return @{ Total = ($allResults | Measure-Object -Sum -Property Total).Sum; Items = $allResults }
    }

    # Console output for specific checks
    if ($CheckIDs) {
        foreach ($result in $allResults) {
            Write-Host "`n$($result.ID) - $($result.Name)" -ForegroundColor Cyan
            if ($result.Items) {
                $validProps = Get-ValidProperties -Items $result.Items -CheckID $result.ID
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
        }
        return
    }

    if ($Text) {
        foreach ($result in $allResults) {
            Write-ToReport ""
            Write-ToReport "$($result.ID) - $($result.Name)"
            Write-ToReport "Total Issues: $($result.Total)"
    
            if ($result.Items) {
                $validProps = Get-ValidProperties -Items $result.Items -CheckID $result.ID
                if ($validProps) {
                    $table = $result.Items | Format-Table -Property $validProps -AutoSize | Out-String
                    Write-ToReport $table.Trim()
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
            if ($result.URL) {
                Write-ToReport "URL: $($result.URL)"
            }
        }
    
        return  @{ Items = $allResults }
    }
    
}