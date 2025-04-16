function Show-EmptyNamespaces {
    param(
        [int]$PageSize = 10, # Number of namespaces per page
        [switch]$Html, # If specified, return an HTML table
        [object]$kubeData,
        [switch]$json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $json) { Clear-Host }
    Write-Host "`n[📂 Empty Namespaces]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Namespace Data..." -ForegroundColor Yellow

    # Fetch full namespace objects first
    if ($KubeData -and $KubeData.Namespaces) {
        $allNamespaces = $KubeData.Namespaces
    } else {
        $allNamespaces = kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    
    # Apply exclusion early, while they’re still objects
    if ($ExcludeNamespaces) {
        $allNamespaces = Exclude-Namespaces -items $allNamespaces
    }
    
    # Now extract the namespace names to check
    $allNsNames = $allNamespaces | ForEach-Object { $_.metadata.name.Trim() }
    
    # Get pod namespaces
    if ($KubeData -and $KubeData.Pods) {
        $pods = $KubeData.Pods.items |
            Where-Object { $_.metadata.namespace -and $_.metadata.namespace.Trim() -ne "" } |
            Group-Object { $_.metadata.namespace.Trim() }
    } else {
        $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.metadata.namespace } |
            Group-Object { $_.metadata.namespace }
    }
    
    $namespacesWithPods = $pods | ForEach-Object { $_.Name.Trim() }
    
    # Calculate empty namespaces
    $emptyNamespaces = $allNsNames | Where-Object { $_ -notin $namespacesWithPods }


    # Force split into an array if it's a multiline string
    if ($emptyNamespaces -is [string]) {
        $emptyNamespaces = $emptyNamespaces -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    } else {
        $emptyNamespaces = @($emptyNamespaces)
    }


    $totalNamespaces = $emptyNamespaces.Count

    if ($totalNamespaces -eq 0) {
        Write-Host "`r🤖 ✅ No empty namespaces found." -ForegroundColor Green

        if ($Json) {
            return [pscustomobject]@{
                TotalEmptyNamespaces = 0
                Namespaces           = @()
            }
        }

        if ($Text -and -not $Html) {
            Write-ToReport "`n[📂 Empty Namespaces]`n"
            Write-ToReport "✅ No empty namespaces found."
        }

        # If not in report mode or HTML mode, prompt to continue
        if (-not $Text -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No empty namespaces found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Namespaces fetched. ($totalNamespaces empty namespaces detected)" -ForegroundColor Green


    if ($Json) {
        return [pscustomobject]@{
            TotalEmptyNamespaces = $totalNamespaces
            Namespaces           = $emptyNamespaces
        }
    }

    # ----- HTML SWITCH -----
    if ($Html) {
        # Build an HTML table. Each row => one namespace
        # Convert the array into PSCustomObjects first
        $namespacesData = $emptyNamespaces | ForEach-Object {
            [PSCustomObject]@{
                "Namespace" = $_
            }
        }

        # Convert to HTML
        $htmlTable = $namespacesData |
        ConvertTo-Html -Fragment -Property "Namespace" |
        Out-String

        # Insert a note about total empty
        $htmlTable = "<p><strong>⚠️ Total Empty Namespaces:</strong> $totalNamespaces</p>" + $htmlTable

        return $htmlTable
    }
    # ----- END HTML SWITCH -----

    # ----- If in report mode, but no -Html switch, do original ascii printing -----
    if ($Text) {
        Write-ToReport "`n[📂 Empty Namespaces]`n"
        Write-ToReport "⚠️ Total Empty Namespaces: $totalNamespaces"
        Write-ToReport "---------------------------------"
        foreach ($namespace in $emptyNamespaces) {
            Write-ToReport "$namespace"
        }
        return
    }

    # ----- Otherwise, do console pagination as before -----
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNamespaces / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📂 Empty Namespaces - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # Speech bubble
        $msg = @(
            "🤖 Empty namespaces exist but contain no running pods.",
            "",
            "📌 These may be unused namespaces that can be cleaned up.",
            "📌 If needed, verify if they contain other resources (Secrets, PVCs).",
            "📌 Deleting an empty namespace will remove all associated resources.",
            "",
            "⚠️ Total Empty Namespaces: $totalNamespaces"
        )

        
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNamespaces)
        
        $tableData = $emptyNamespaces | Select-Object -Skip $startIndex -First ($endIndex - $startIndex) | ForEach-Object {
            [PSCustomObject]@{ Namespace = $_ }
        }
        
        if ($tableData) {
            $tableData | Format-Table Namespace -AutoSize | Out-Host
        }
        

        # Pagination
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}

function Check-ResourceQuotas {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📊 Missing or Weak ResourceQuotas]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching ResourceQuota data..." -ForegroundColor Yellow
    }

    try {
        $quotas = if ($KubeData -and $KubeData.ResourceQuotas) {
            $KubeData.ResourceQuotas
        } else {
            $raw = if ($Namespace) {
                kubectl get resourcequotas -n $Namespace -o json 2>&1
            } else {
                kubectl get resourcequotas --all-namespaces -o json 2>&1
            }
            if ($raw -match "No resources found") {
                $quotas = @()
            } else {
                ($raw | ConvertFrom-Json).items
            }
        }

        $namespaces = if ($KubeData -and $KubeData.Namespaces) {
            $KubeData.Namespaces
        } else {
            kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving ResourceQuota data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving ResourceQuota data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $namespaces = Exclude-Namespaces -items $namespaces
        $quotaNamespaces = $namespaces | ForEach-Object { $_.metadata.name }
        $quotas = $quotas | Where-Object { $_.metadata.namespace -in $quotaNamespaces }
    }    

    $results = @()
    foreach ($ns in $namespaces) {
        $nsName = $ns.metadata.name
        $nsQuotas = $quotas | Where-Object { $_.metadata.namespace -eq $nsName }

        if (-not $nsQuotas) {
            $results += [PSCustomObject]@{
                Namespace = $nsName
                Issue     = "❌ No ResourceQuota defined"
            }
        } else {
            $hasCPU = $false
            $hasMemory = $false
            $hasPods = $false

            foreach ($quota in $nsQuotas) {
                $scopes = $quota.status.hard.PSObject.Properties.Name
                if ($scopes -contains "requests.cpu" -or $scopes -contains "limits.cpu") { $hasCPU = $true }
                if ($scopes -contains "requests.memory" -or $scopes -contains "limits.memory") { $hasMemory = $true }
                if ($scopes -contains "pods") { $hasPods = $true }
            }

            if (-not ($hasCPU -and $hasMemory -and $hasPods)) {
                $missing = @()
                if (-not $hasCPU) { $missing += "CPU" }
                if (-not $hasMemory) { $missing += "Memory" }
                if (-not $hasPods) { $missing += "Pods" }
                $results += [PSCustomObject]@{
                    Namespace = $nsName
                    Issue     = "⚠️ Missing: $($missing -join ', ')"
                }
            }
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All namespaces have strong ResourceQuotas.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ All namespaces have strong ResourceQuotas." -ForegroundColor Green
        return
    }

    Write-Host "`r🤖 ✅ ResourceQuota issues found. ($total affected namespaces)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        $htmlTable = $results | Sort-Object Namespace |
            ConvertTo-Html -Fragment -Property Namespace, Issue | Out-String
        return "<p><strong>⚠️ Namespaces with ResourceQuota issues:</strong> $total</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[📊 Missing or Weak ResourceQuotas]`n"
        Write-ToReport "⚠️ Total Issues: $total"
        $tableString = $results | Format-Table Namespace, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[📊 ResourceQuota Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 These namespaces lack full ResourceQuota enforcement.",
                "",
                "📌 Why this matters:",
                "   - Quotas protect the cluster from resource abuse.",
                "   - Helps prevent noisy neighbor issues.",
                "",
                "⚠️ Total Issues: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-NamespaceLimitRanges {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📐 Missing LimitRanges]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching LimitRange data..." -ForegroundColor Yellow
    }

    try {
        $limitRanges = if ($KubeData -and $KubeData.LimitRanges) {
            $KubeData.LimitRanges
        } else {
            kubectl get limitranges --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $namespaces = if ($KubeData -and $KubeData.Namespaces) {
            $KubeData.Namespaces
        } else {
            kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error fetching LimitRanges: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving LimitRange data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $namespaces = Exclude-Namespaces -items $namespaces
        $validNamespaces = $namespaces | ForEach-Object { $_.metadata.name }
        $limitRanges = $limitRanges | Where-Object { $_.metadata.namespace -in $validNamespaces }
    }

    $results = @()

    foreach ($ns in $namespaces) {
        $nsName = $ns.metadata.name
        $hasLimitRange = $limitRanges | Where-Object { $_.metadata.namespace -eq $nsName }

        if (-not $hasLimitRange) {
            $results += [PSCustomObject]@{
                Namespace = $nsName
                Issue     = "❌ No LimitRange defined"
            }
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All namespaces have a LimitRange.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ All namespaces have a LimitRange." -ForegroundColor Green
        return
    }

    Write-Host "`r🤖 ✅ LimitRange issues found. ($total namespaces affected)" -ForegroundColor Green

    if ($Json) {
        return @{ Total = $total; Items = $results }
    }

    if ($Html) {
        $htmlTable = $results | Sort-Object Namespace |
            ConvertTo-Html -Fragment -Property Namespace, Issue | Out-String
        return "<p><strong>⚠️ Namespaces missing LimitRanges:</strong> $total</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[📐 Missing LimitRanges]`n⚠️ Total: $total"
        $tableString = $results | Format-Table Namespace, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[📐 LimitRange Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 LimitRanges define default and max CPU/memory limits for containers.",
                "",
                "📌 Why this matters:",
                "   - Prevents runaway pods from consuming unbounded resources.",
                "   - Sets defaults if workloads don’t define them explicitly.",
                "",
                "⚠️ Total affected namespaces: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
