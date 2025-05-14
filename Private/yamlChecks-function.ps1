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
    $thresholds = Get-KubeBuddyThresholds -Silent

    # Ensure required modules
    try {
        Import-Module powershell-yaml -ErrorAction Stop
        # Import all PowerShell modules from $PSScriptRoot
        Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            Import-Module $_.FullName -ErrorAction Stop
        }
    }
    catch {
        Write-Host "❌ Failed to load required module: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Failed to load required module.</strong></p>" }
        if ($Json) { return @{ Error = "Failed to load required module: $_" } }
        Read-Host "🤖 Error. Check logs or output above. Press Enter to continue"
        return
    }

    # if Prometheus settings are on the KubeData object, adopt them
    if ($KubeData.PrometheusUrl) {
        $PrometheusUrl = $KubeData.PrometheusUrl
        $PrometheusMode = $KubeData.PrometheusMode
        $PrometheusUsername = $KubeData.PrometheusUsername
        $PrometheusPassword = $KubeData.PrometheusPassword
        $PrometheusBearerTokenEnv = $KubeData.PrometheusBearerTokenEnv
        $PrometheusHeaders = $kubedata.PrometheusHeaders
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
    
        # If check has predefined properties, use them
        if ($checkSpecificProperties.ContainsKey($CheckID)) {
            return $checkSpecificProperties[$CheckID]
        }
    
        # If no items, return empty array
        if (-not $Items) {
            return @()
        }
    
        # Get properties from the first item to preserve order
        $properties = $Items[0].PSObject.Properties.Name
    
        # Filter out properties with no data across all items
        $validProps = @()
        foreach ($prop in $properties) {
            $hasData = $Items | Where-Object {
                $_.$prop -ne $null -and $_.$prop -ne "" -and $_.$prop -ne "-"
            }
            if ($hasData) {
                $validProps += $prop
            }
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
        Read-Host "🤖 Error. Check logs or output above. Press Enter to continue"
        return
    }

    if (-not $checkFiles) {
        Write-Host "✅ No custom check YAML files found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No custom checks found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        return
    }

    # Initialize thread-safe collection for results
    $allResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

    # Process checks in parallel and collect results
    $parallelResults = $checkFiles | ForEach-Object -Parallel {
        # Re-import required modules in parallel scope
        try {
            Import-Module powershell-yaml -ErrorAction Stop
            # Import all PowerShell modules from $using:PSScriptRoot
            Get-ChildItem -Path $using:PSScriptRoot -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                Import-Module $_.FullName -ErrorAction Stop
            }
        }
        catch {
            $errorMessage = "❌ Failed to load required module in parallel scope: $_"
            Write-Host $errorMessage -ForegroundColor Red
            return @{
                ID    = "Unknown"
                Name  = $_.Name
                Error = $errorMessage
            }
        }

        function Evaluate-PrometheusCheckResult {
            param (
                [object]$Metric,
                [double]$Expected,
                [string]$Operator,
                [string]$FailMessage
            )
        
            $values = $Metric.values
            if (-not $values -or $values.Count -eq 0) {
                return $null
            }
        
            $avg = ($values | ForEach-Object { [double]($_[1]) }) | Measure-Object -Average | Select-Object -ExpandProperty Average
        
            $failed = $false
            switch ($Operator.ToLower()) {
                "greater_than" { $failed = $avg -gt $Expected }
                "less_than" { $failed = $avg -lt $Expected }
                "equals" { $failed = [math]::Round($avg, 5) -eq [math]::Round($Expected, 5) }
                default { return $null }  # unknown operator, skip
            }
        
            if (-not $failed) {
                return $null
            }
        
            # Build result object
            $labels = $Metric.metric.PSObject.Properties | ForEach-Object {
                "$($_.Name): $($_.Value)"
            } -join ", "
        
            return [pscustomobject]@{
                MetricLabels = $labels
                Average      = "{0:N4}" -f $avg
                Message      = $FailMessage
            }
        }        

        $localResults = @()

        try {
            $yamlContent = Get-Content $_.FullName -Raw | ConvertFrom-Yaml
            if (-not $yamlContent.checks) {
                return
            }

            $excludedCheckIDs = $using:thresholds.excluded_checks
     
            foreach ($check in $yamlContent.checks) {
                # Skip if excluded AND not explicitly requested by -CheckIDs
                if ($excludedCheckIDs -contains $check.ID -and -not ($using:CheckIDs -and $check.ID -in $using:CheckIDs)) {
                    Write-Host "⏭️  Skipping excluded check: $($check.ID)" -ForegroundColor DarkGray
                    continue
                }
                # Filter checks if CheckIDs specified
                if ($using:CheckIDs -and $check.ID -notin $using:CheckIDs) {
                    continue
                }

                Write-Host "🤖 Processing check: $($check.ID) - $($check.Name)..." -ForegroundColor Cyan

                # Custom script block execution
                if ($check.Script) {
                    try {
                        # Define disallowed kubectl commands
                        $disallowedPatterns = @(
                            '\bkubectl\s+(create|run|edit|delete|patch|apply|replace|scale|rollout|annotate|label|taint|cordon|uncordon|drain|evict)\b',
                            '\bkubectl\s+.*\s--force\b',
                            '\bkubectl\s+.*\s--overwrite\b',
                            '\bkubectl\s+.*\s--grace-period\b',
                            '\bhelm\s+(install|upgrade|uninstall|rollback|delete|dep\s+update|template)\b',
                            '\bRemove-Item\b',
                            '\bSet-Content\b',
                            '\bNew-Item\b',
                            '\bStop-Process\b',
                            '\bStart-Process\b',
                            '[;\|]\s*kubectl\s+',
                            '[;\|]\s*helm\s+',
                            'kubectl\s+.*[`\\]\s*.*'
                        )

                        $scriptContent = $check.Script
                        $disallowedCommandFound = $false
                        $matchedPattern = $null

                        foreach ($pattern in $disallowedPatterns) {
                            if ($scriptContent -match $pattern) {
                                $disallowedCommandFound = $true
                                $matchedPattern = $pattern
                                break
                            }
                        }

                        if ($disallowedCommandFound) {
                            $errorMessage = "❌ Check $($check.ID) contains disallowed command pattern: `$matchedPattern`. Blocking execution."
                            Write-Host $errorMessage -ForegroundColor Red
                            $localResults += @{
                                ID    = $check.ID
                                Name  = $check.Name
                                Error = $errorMessage
                            }
                            continue
                        }

                        $scriptBlock = [scriptblock]::Create($check.Script)
                        $scriptResult = if ($check.ID -eq "NODE002") {
                            & $scriptBlock -KubeData $using:KubeData -Thresholds $using:thresholds
                        }
                        else {
                            & $scriptBlock -KubeData $using:KubeData -Namespace $using:Namespace -ExcludeNamespaces:$using:ExcludeNamespaces
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
                            Recommendation = $check.Recommendation  # Store the raw recommendation (hashtable or string)
                            URL            = $check["URL"]
                            Items          = @()
                            Total          = 0
                        }

                        if ($scriptResult -is [hashtable] -and $scriptResult.ContainsKey("Items")) {
                            $items = $scriptResult["Items"]
                            $checkResult.Items = if ($items -is [array]) { $items } else { @($items) }
                            $checkResult.Total = if ($scriptResult.ContainsKey("IssueCount")) {
                                $scriptResult["IssueCount"]
                            }
                            else {
                                $checkResult.Items.Count
                            }
                        }
                        elseif ($scriptResult -is [array]) {
                            $checkResult.Items = $scriptResult
                            $checkResult.Total = $scriptResult.Count
                        }
                        elseif ($scriptResult) {
                            # Catch anything else not a hashtable or array, but still not null
                            $checkResult.Items = @($scriptResult)
                            $checkResult.Total = 1
                        }    
                        
                        if ($scriptResult -is [hashtable] -and $scriptResult.ContainsKey("UsedPrometheus")) {
                            $checkResult.UsedPrometheus = $scriptResult.UsedPrometheus
                        }
                        elseif ($scriptResult -is [array] -and $scriptResult[0]?.UsedPrometheus -ne $null) {
                            $checkResult.UsedPrometheus = $scriptResult[0].UsedPrometheus
                        }                                            

                        if ($checkResult.Total -eq 0) {
                            $checkResult.Message = "No issues detected for $($check.Name)."
                        }

                        $localResults += $checkResult
                        Write-Host "`✅ Completed check: $($check.ID) - $($check.Name)                     " -ForegroundColor Green
                    }
                    catch {
                        Write-Host "❌ Error executing script for $($check.ID): $_" -ForegroundColor Red
                        $localResults += @{
                            ID    = $check.ID
                            Name  = $check.Name
                            Error = "Script block execution failed: $_"
                        }
                    }
                    continue
                }

                if ($check.Prometheus) {
                    try {
                        # Derive URL & Mode: prefer per-check override, else fall back to global
                        $url = if ($check.Prometheus.Url) { $check.Prometheus.Url } else { $using:PrometheusUrl }
                        $headers = $using:PrometheusHeaders

                        # lookup expected threshold:
                        # if the YAML Expected is a string key in $thresholds, use that value,
                        # otherwise cast it directly to double
                        if ($check.Expected -is [string] -and $thresholds.ContainsKey($check.Expected)) {
                            $expectedValue = [double]$thresholds[$check.Expected]
                        }
                        else {
                            $expectedValue = [double]$check.Expected
                        }

                        # Time window driven by your YAML Range.Duration
                        $endTime = (Get-Date).ToUniversalTime()
                        # pull in the Duration string (e.g. "24h", "1h", "30m", "2d")
                        $durStr = $check.Prometheus.Range.Duration

                        # parse into a TimeSpan
                        if ($durStr -match '^(\d+)([hmd])$') {
                            $num = [int]$Matches[1]
                            $unit = $Matches[2]
                            switch ($unit) {
                                'h' { $ts = New-TimeSpan -Hours   $num }
                                'm' { $ts = New-TimeSpan -Minutes $num }
                                'd' { $ts = New-TimeSpan -Days    $num }
                            }
                        }
                        else {
                            # fallback: assume it's just a number of hours
                            $ts = New-TimeSpan -Hours ([double]$durStr)
                        }

                        $startTime = $endTime.Add(-$ts).ToUniversalTime().ToString("o")
                        $endTime = $endTime.ToString("o")

                        #  Execute the query
                        $result = Get-PrometheusData `
                            -Query   $check.Prometheus.Query `
                            -Url     $url `
                            -Headers $headers `
                            -UseRange `
                            -StartTime $startTime `
                            -EndTime   $endTime `
                            -Step      $check.Prometheus.Range.Step
                
                        $items = @()
                        foreach ($r in $result.Results) {
                            $eval = Evaluate-PrometheusCheckResult `
                                -Metric $r `
                                -Expected $expectedValue `
                                -Operator $check.Operator `
                                -FailMessage $check.FailMessage
                        
                            if ($eval) {
                                $items += $eval
                            }
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
                            Recommendation = $check.Recommendation
                            URL            = $check.URL
                            Items          = $items
                            Total          = $items.Count
                        }
                
                        $localResults += $checkResult
                        Write-Host "✅ Completed Prometheus check: $($check.ID) - $($check.Name)                     " -ForegroundColor Green
                    }
                    catch {
                        Write-Host "❌ Prometheus check failed for $($check.ID): $_" -ForegroundColor Red
                        $localResults += @{
                            ID    = $check.ID
                            Name  = $check.Name
                            Error = "Prometheus check failed: $_"
                        }
                    }
                    continue
                }                

                # Non-script check logic
                $data = $null
                $kubeData = $using:KubeData  # Assign to local variable to avoid $using: in expressions
                if ($kubeData -and $check.ResourceKind -in $kubeData.PSObject.Properties.Name) {
                    $data = $kubeData.($check.ResourceKind).items
                }
                else {
                    $kubectlCmd = if ($using:Namespace) {
                        "$($using:kubectl) get $($check.ResourceKind) -n $($using:Namespace) -o json"
                    }
                    else {
                        "$($using:kubectl) get $($check.ResourceKind) --all-namespaces -o json"
                    }
                    $maxRetries = 3
                    $retryDelay = 2
                    $attempt = 0
                    $data = $null
                    $success = $false

                    while (-not $success -and $attempt -lt $maxRetries) {
                        try {
                            $output = Invoke-Expression $kubectlCmd 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                throw "kubectl failed: $output"
                            }
                            $data = ($output | ConvertFrom-Json).items
                            $success = $true
                        }
                        catch {
                            $attempt++
                            if ($attempt -lt $maxRetries) {
                                Start-Sleep -Seconds $retryDelay
                            }
                            else {
                                Write-Host "❌ Failed to fetch $($check.ResourceKind) data after $maxRetries attempts: $_" -ForegroundColor Red
                                $localResults += @{
                                    ID    = $check.ID
                                    Name  = $check.Name
                                    Error = "Failed to fetch data after $maxRetries attempts: $_"
                                }
                                continue
                            }
                        }
                    }
                }

                if (-not $data) {
                    Write-Host "❌ No $($check.ResourceKind) data available." -ForegroundColor Red
                    $localResults += @{
                        ID      = $check.ID
                        Name    = $check.Name
                        Message = "No $($check.ResourceKind) data available."
                    }
                    continue
                }

                if ($using:Namespace -and $data[0].metadata.PSObject.Properties.Name -contains 'namespace') {
                    $data = $data | Where-Object { $_.metadata.namespace -eq $using:Namespace }
                }

                if ($using:ExcludeNamespaces) {
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
                    Recommendation = $check.Recommendation  # Store the raw recommendation (hashtable or string)
                    URL            = $check["URL"]
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
                            default { Write-Host "❌ Unsupported operator: $($check.Operator)" -ForegroundColor Red; continue }
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
                $localResults += $checkResult
                Write-Host "`r✅ Completed check: $($check.ID) - $($check.Name)      " -ForegroundColor Green
            }
        }
        catch {
            Write-Host "❌ Error processing $($_.Name): $_" -ForegroundColor Red
            $localResults += @{
                ID    = "Unknown"
                Name  = $_.Name
                Error = "Error processing file: $_"
            }
        }

        # Return results from this parallel iteration
        $localResults
    } -ThrottleLimit 5

    # Aggregate results into ConcurrentBag
    foreach ($result in $parallelResults) {
        if ($result) {
            if ($result -is [array]) {
                $result | ForEach-Object { $allResults.Add($_) }
            }
            else {
                $allResults.Add($result)
            }
        }
    }

    # Convert ConcurrentBag to array and sort by Check ID
    $allResults = $allResults.ToArray() | Sort-Object -Property ID

    # HTML output
    if ($Html) {
        $sectionGroups = @{}
        $collapsibleSectionMap = @{}
        $alwaysCollapsibleCheckIDs = @("NODE001", "NODE002")
        $alwaysShowRecommendationsCheckIDs = @()  # Define checks that should always show recommendations, even with no issues

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
                $usedPrometheus = if ($check.ID -eq "NODE002" -and ($check.UsedPrometheus -eq $true)) { $true } else { $false }
                $prometheusSuffix = if ($check.ID -eq "NODE002" -and $usedPrometheus) { " (Last 24h)" } else { "" }
                
                # Tooltip generation can stay as-is
                $tooltipText = ""
                if ($check.Description) {
                    $tooltipText = $check.Description
                }
                if ($check.ID -eq "NODE002") {
                    $sourceText = if ($usedPrometheus) {
                        "Data source: Prometheus (24h average)"
                    }
                    else {
                        "Data source: kubectl top nodes (snapshot)"
                    }
                    $tooltipText = if ($tooltipText) { "$tooltipText<br><br>$sourceText" } else { $sourceText }
                }
                $tooltip = if ($tooltipText) {
                    "<span class='tooltip'><span class='info-icon'>i</span><span class='tooltip-text'>$tooltipText</span></span>"
                }
                else {
                    ""
                }
                
                $header = "<h2 id='$($check.ID)'>$($check.ID) - $($check.Name)$prometheusSuffix $tooltip</h2>"


                $resourceKind = $check.ResourceKind
                $displayNames = Get-ResourceKindDisplayNames -ResourceKind $resourceKind
                $resourceKindPlural = $displayNames.Plural

                $summary = if ($check.Total -gt 0) {
                    "<p>⚠️ Total $resourceKindPlural with Issues: $($check.Total)</p>"
                }
                else {
                    "<p>✅ All $resourceKindPlural are healthy.</p>"
                }

                # Recommendation HTML: Handle both hashtable and plain string recommendations
                $recommendationHtml = if ($check.Recommendation) {
                    if ($check.Recommendation -is [hashtable] -and $check.Recommendation.html) {
                        $recContent = $check.Recommendation.html
                        # Append the URL as an <li> with "Docs: " label if not already present
                        if ($check.URL -and ($recContent -notmatch [regex]::Escape($check.URL))) {
                            # Extract a display name from the URL
                            $urlDisplayName = $check.URL -replace '.*#', ''  # Get the fragment after the last '#'
                            if (-not $urlDisplayName) {
                                $urlDisplayName = ($check.URL -split '/')[-1]  # Fallback to last path segment
                            }
                            # Clean up and format the display name
                            $urlDisplayName = $urlDisplayName -replace '-', ' '
                            $urlDisplayName = (Get-Culture).TextInfo.ToTitleCase($urlDisplayName)
                            $urlDisplayName = "Kubernetes $urlDisplayName"
                            $urlHtml = "<li><strong>Docs:</strong> <a href='$($check.URL)' target='_blank'>$urlDisplayName</a></li>"

                            # Check if recContent contains a <ul>
                            if ($recContent -match '</ul>') {
                                # Insert the <li> before the closing </ul>
                                $recContent = $recContent -replace '</ul>', "$urlHtml</ul>"
                            }
                            else {
                                # If no <ul>, wrap the URL in a new <ul>
                                $recContent += "<ul>$urlHtml</ul>"
                            }
                        }
                        @"
<div class="recommendation-card">
<div class="recommendation-banner">
  <span class="material-icons">tips_and_updates</span>
  Recommended Actions
</div>
  $recContent
</div>
<div style='height: 15px;'></div>
"@
                    }
                    else {
                        # Handle plain string recommendations by wrapping in recommendation-card
                        $recContent = $check.Recommendation
                        # Append the URL as an <li> with "Docs: " label if not already present
                        if ($check.URL -and ($recContent -notmatch [regex]::Escape($check.URL))) {
                            # Extract a display name from the URL
                            $urlDisplayName = $check.URL -replace '.*#', ''  # Get the fragment after the last '#'
                            if (-not $urlDisplayName) {
                                $urlDisplayName = ($check.URL -split '/')[-1]  # Fallback to last path segment
                            }
                            # Clean up and format the display name
                            $urlDisplayName = $urlDisplayName -replace '-', ' '
                            $urlDisplayName = (Get-Culture).TextInfo.ToTitleCase($urlDisplayName)
                            $urlDisplayName = "Kubernetes $urlDisplayName"
                            $urlHtml = "<li><strong>Docs:</strong> <a href='$($check.URL)' target='_blank'>$urlDisplayName</a></li>"

                            # Wrap the plain string in a <ul> and append the URL
                            $recContent = "<ul><li>$recContent</li>$urlHtml</ul>"
                        }
                        else {
                            # If no URL, still wrap the plain string in a <ul>
                            $recContent = "<ul><li>$recContent</li></ul>"
                        }
                        @"
<div class="recommendation-card">
<div class="recommendation-banner">
  <span class="material-icons">tips_and_updates</span>
  Recommended Actions
</div>
  $recContent
</div>
<div style='height: 15px;'></div>
"@
                    }
                }
                else {
                    # If no recommendation, just show the URL if it exists
                    if ($check.URL) {
                        # Extract a display name from the URL
                        $urlDisplayName = $check.URL -replace '.*#', ''  # Get the fragment after the last '#'
                        if (-not $urlDisplayName) {
                            $urlDisplayName = ($check.URL -split '/')[-1]  # Fallback to last path segment
                        }
                        # Clean up and format the display name
                        $urlDisplayName = $urlDisplayName -replace '-', ' '
                        $urlDisplayName = (Get-Culture).TextInfo.ToTitleCase($urlDisplayName)
                        $urlDisplayName = "Kubernetes $urlDisplayName"
                        $urlHtml = "<li><strong>Docs:</strong> <a href='$($check.URL)' target='_blank'>$urlDisplayName</a></li>"
                        @"
<div class="recommendation-card">
  <ul>
    $urlHtml
  </ul>
</div>
<div style='height: 15px;'></div>
"@
                    }
                    else {
                        ""
                    }
                }

                $recommendationSection = ""
                # Show recommendation section if there are issues or if the check is in alwaysShowRecommendationsCheckIDs
                if ($recommendationHtml -and ($check.Total -gt 0 -or $check.ID -in $alwaysShowRecommendationsCheckIDs)) {
                    $recommendationSection = ConvertToCollapsible -Id "$($check.ID)_recommendations" -defaultText "Show Recommendations" -content $recommendationHtml
                }
                # Additional case: If there's a URL but no recommendation, show it when there are issues
                elseif ($check.URL -and $check.Total -gt 0) {
                    # Extract a display name from the URL
                    $urlDisplayName = $check.URL -replace '.*#', ''  # Get the fragment after the last '#'
                    if (-not $urlDisplayName) {
                        $urlDisplayName = ($check.URL -split '/')[-1]  # Fallback to last path segment
                    }
                    # Clean up and format the display name
                    $urlDisplayName = $urlDisplayName -replace '-', ' '
                    $urlDisplayName = (Get-Culture).TextInfo.ToTitleCase($urlDisplayName)
                    $urlDisplayName = "Kubernetes $urlDisplayName"
                    $urlHtml = "<li><strong>Docs:</strong> <a href='$($check.URL)' target='_blank'>$urlDisplayName</a></li>"
                    $urlHtml = @"
<div class="recommendation-card">
  <ul>
    $urlHtml
  </ul>
</div>
<div style='height: 15px;'></div>
"@
                    $recommendationSection = ConvertToCollapsible -Id "$($check.ID)_recommendations" -defaultText "Show Recommendations" -content $urlHtml
                }

                # Table content for findings
                $tableContent = if ($check.Items) {
                    $validProps = Get-ValidProperties -Items $check.Items -CheckID $check.ID
                    if ($validProps) {
                        # Manually build the table HTML
                        $tableHtml = "<table>`n<tr>"
                        # Add headers
                        foreach ($prop in $validProps) {
                            $tableHtml += "<th>$prop</th>"
                        }
                        $tableHtml += "</tr>`n"
                        # Add rows
                        foreach ($item in $check.Items) {
                            $tableHtml += "<tr>"
                            foreach ($prop in $validProps) {
                                $value = $item.$prop
                                # For status columns, assume the value is already HTML and don't escape it
                                if ($prop -in @("CPU Status", "Mem Status", "Disk Status")) {
                                    $tableHtml += "<td>$value</td>"
                                }
                                else {
                                    # Escape other columns to prevent XSS
                                    $escapedValue = $value -replace '<', '<' `
                                        -replace '>', '>' `
                                        -replace '"', '"'
                                    $tableHtml += "<td>$escapedValue</td>"
                                }
                            }
                            $tableHtml += "</tr>`n"
                        }
                        $tableHtml += "</table>"
                        $tableHtml
                    }
                    else {
                        "<p>No valid data to display.</p>"
                    }
                }
                else {
                    if ($check.ID -in $alwaysCollapsibleCheckIDs) {
                        $validProps = Get-ValidProperties -Items @() -CheckID $check.ID
                        if ($validProps) {
                            # Build an empty table for checks that should always be displayed
                            $tableHtml = "<table>`n<tr>"
                            foreach ($prop in $validProps) {
                                $tableHtml += "<th>$prop</th>"
                            }
                            $tableHtml += "</tr></table>"
                            $tableHtml
                        }
                        else {
                            "<p>No data available for this check.</p>"
                        }
                    }
                    else {
                        ""
                    }
                }

                # Create the findings collapsible section
                $findingsSection = if ($check.Items -or ($check.ID -in $alwaysCollapsibleCheckIDs -and $tableContent)) {
                    ConvertToCollapsible -Id $check.ID -defaultText "Show Findings" -content $tableContent
                }
                else {
                    ""
                }

                # Combine the sections: header, summary, recommendations, then findings
                $sectionHtml += @"
$header
$summary
<div class='table-container'>
  $recommendationSection
  $findingsSection
</div>
"@
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
    
    # JSON output
    if ($Json) {
        return @{ Total = ($allResults | Measure-Object -Sum -Property Total).Sum; Items = $allResults }
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
    
        return @{ Items = $allResults }
    }

    if (-not $Text -and -not $Html -and -not $Json) {
        return @{ Items = $allResults }
    }
}