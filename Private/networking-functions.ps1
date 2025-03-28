function Show-ServicesWithoutEndpoints {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔍 Services Without Endpoints]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Service Data..." -ForegroundColor Yellow

    try {
        if ($null -ne $KubeData) {
            $services = $KubeData.Services.items | Where-Object { $_.spec.type -ne "ExternalName" }
            $endpointsRaw = $KubeData.Endpoints.items
        } else {
            $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json |
                Select-Object -ExpandProperty items |
                Where-Object { $_.spec.type -ne "ExternalName" }

            $endpointsRaw = kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json |
                Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch service or endpoint data: $_" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n❌ Error: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $services = Exclude-Namespaces -items $services
        $endpointsRaw = Exclude-Namespaces -items $endpointsRaw
    }

    Write-Host "`r🤖 ✅ Services fetched. (Total: $($services.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Endpoints..." -ForegroundColor Yellow

    # Build endpoint lookup
    $endpoints = $endpointsRaw | Group-Object { $_.metadata.namespace + "/" + $_.metadata.name }
    $endpointsLookup = @{}
    foreach ($ep in $endpoints) {
        $endpointsLookup[$ep.Name] = $true
    }

    # Filter services without endpoints
    $servicesWithoutEndpoints = $services | Where-Object {
        -not $endpointsLookup.ContainsKey($_.metadata.namespace + "/" + $_.metadata.name)
    }

    $totalServices = $servicesWithoutEndpoints.Count
    Write-Host "`r🤖 ✅ Endpoint analysis complete. ($totalServices services without endpoints)" -ForegroundColor Green

    if ($totalServices -eq 0) {
        Write-Host "`r🤖 ✅ All services have endpoints." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n✅ All services have endpoints."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ All services have endpoints.</strong></p>"
        }
        return
    }

    # Table content
    $tableData = $servicesWithoutEndpoints | ForEach-Object {
        [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            Service   = $_.metadata.name
            Type      = $_.spec.type
            Status    = "⚠️ No Endpoints"
        }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Service, Type, Status |
            Out-String
        return "<p><strong>⚠️ Total Services Without Endpoints:</strong> $totalServices</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔍 Services Without Endpoints]`n⚠️ Total: $totalServices"
        $tableString = $tableData |
            Format-Table Namespace, Service, Type, Status -AutoSize |
            Out-String
        Write-ToReport $tableString
        return
    }

    # Console pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalServices / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔍 Services Without Endpoints - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 These services lack endpoints.",
                "",
                "📌 Endpoints are needed to route traffic to pods.",
                "   - Check if matching pods exist.",
                "   - Validate service selectors.",
                "",
                "⚠️ Total: $totalServices"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $start = $currentPage * $PageSize
        $slice = $tableData | Select-Object -Skip $start -First $PageSize

        if ($slice) {
            $slice | Format-Table Namespace, Service, Type, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PubliclyAccessibleServices {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🌐 Publicly Accessible Services]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Services..." -ForegroundColor Yellow

    try {
        $services = if ($null -ne $KubeData) {
            $KubeData.Services.items
        } else {
            kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch service data: $_" -ForegroundColor Red
        if ($Html) { return "<p>❌ Failed to fetch service data.</p>" }
        return
    }

    if (-not $services) {
        Write-Host "`r🤖 ❌ No services found." -ForegroundColor Red
        if ($Html) { return "<p>❌ No services found.</p>" }
        return
    }

    if ($ExcludeNamespaces) {
        $services = Exclude-Namespaces -items $services
    }

    Write-Host "`r🤖 ✅ Services fetched. ($($services.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing for external exposure..." -ForegroundColor Yellow

    $publicServices = $services | Where-Object {
        $_.spec.type -in @("LoadBalancer", "NodePort")
    }

    $totalPublic = $publicServices.Count
    Write-Host "`r🤖 ✅ Analysis complete. ($totalPublic exposed services)" -ForegroundColor Green

    if ($totalPublic -eq 0) {
        Write-Host "✅ No publicly accessible services found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🌐 Publicly Accessible Services]`n✅ No publicly accessible services found."
        }
        if ($Html) {
            return "<p><strong>✅ No publicly accessible services found.</strong></p>"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    $tableData = foreach ($svc in $publicServices) {
        [PSCustomObject]@{
            Namespace  = $svc.metadata.namespace
            Service    = $svc.metadata.name
            Type       = $svc.spec.type
            Ports      = ($svc.spec.ports | ForEach-Object { "$($_.port)/$($_.protocol)" }) -join ", "
            ExternalIP = if ($svc.status.loadBalancer.ingress) {
                ($svc.status.loadBalancer.ingress | ForEach-Object { $_.ip }) -join ", "
            } else {
                "Pending"
            }
        }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Service, Type, Ports, ExternalIP |
            Out-String
        return "<p><strong>⚠️ Total Public Services Found:</strong> $totalPublic</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🌐 Publicly Accessible Services]`n⚠️ Total Public Services Found: $totalPublic"
        $tableString = $tableData | Format-Table Namespace, Service, Type, Ports, ExternalIP -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPublic / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🌐 Publicly Accessible Services - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 Services of type LoadBalancer or NodePort may be exposed to the internet.",
                "",
                "📌 This check identifies services with potential public access.",
                "   - External IPs from LoadBalancers.",
                "   - NodePort access on each cluster node.",
                "",
                "⚠️ Review these services for exposure risk.",
                "",
                "⚠️ Total Public Services Found: $totalPublic"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPublic)

        $tableData[$startIndex..($endIndex - 1)] |
            Format-Table Namespace, Service, Type, Ports, ExternalIP -AutoSize |
            Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}