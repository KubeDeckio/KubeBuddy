function Show-ServicesWithoutEndpoints {
    param(
        [int]$PageSize = 10, # Number of services per page
        [switch]$Html         # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔍 Services Without Endpoints]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Service Data..." -ForegroundColor Yellow

    # Fetch all services
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Where-Object { $_.spec.type -ne "ExternalName" }  # Exclude ExternalName services

    if (-not $services) {
        Write-Host "`r🤖 ❌ Failed to fetch service data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "❌ Failed to fetch service data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Services fetched. (Total: $($services.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Fetching Endpoint Data..." -ForegroundColor Yellow

    # Fetch endpoints
    $endpoints = kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Group-Object { $_.metadata.namespace + "/" + $_.metadata.name }

    if (-not $endpoints) {
        Write-Host "`r🤖 ❌ Failed to fetch endpoint data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "❌ Failed to fetch endpoint data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Endpoints fetched. (Total: $($endpoints.Count))" -ForegroundColor Green
    Write-Host "`n🤖 Analyzing Services..." -ForegroundColor Yellow

    # Convert endpoints to a lookup table
    $endpointsLookup = @{}
    foreach ($ep in $endpoints) {
        $endpointsLookup[$ep.Name] = $true
    }

    # Filter services without endpoints
    $servicesWithoutEndpoints = $services | Where-Object {
        -not $endpointsLookup.ContainsKey($_.metadata.namespace + "/" + $_.metadata.name)
    }

    $totalServices = $servicesWithoutEndpoints.Count

    if ($totalServices -eq 0) {
        Write-Host "`r🤖 ✅ All services have endpoints." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "✅ All services have endpoints."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p>✅ All services have endpoints.</p>" }
        return
    }

    Write-Host "`r🤖 ✅ Service analysis complete. ($totalServices services without endpoints detected)" -ForegroundColor Green

    # If -Html, return an HTML table
    if ($Html) {
        $tableData = foreach ($svc in $servicesWithoutEndpoints) {
            [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️ No Endpoints"
            }
        }

        $htmlTable = $tableData |
        ConvertTo-Html -Fragment -Property Namespace, Service, Type, Status -PreContent "<h2>Services Without Endpoints</h2>" |
        Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Services Without Endpoints:</strong> $totalServices</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode but not HTML
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔍 Services Without Endpoints]`n"
        Write-ToReport "⚠️ Total Services Without Endpoints: $totalServices" 
        $tableData = @()
        foreach ($svc in $servicesWithoutEndpoints) {
            $tableData += [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️ No Endpoints"
            }
        }
        $tableString = $tableData | Format-Table Namespace, Service, Type, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination approach
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalServices / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔍 Services Without Endpoints - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 Kubernetes services route traffic, but require endpoints to work.",
            "",
            "📌 This check identifies services that have no associated endpoints.",
            "   - No endpoints could mean no running pods match service selectors.",
            "   - It may also indicate misconfigurations or orphaned services.",
            "",
            "⚠️ Investigate these services to confirm if they are required.",
            "",
            "⚠️ Total Services Without Endpoints: $totalServices"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalServices)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $svc = $servicesWithoutEndpoints[$i]
            [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️"
            } | ForEach-Object { $tableData += $_ }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Service, Type, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}