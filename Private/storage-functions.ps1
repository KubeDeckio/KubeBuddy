function Show-UnusedPVCs {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[💾 Unused Persistent Volume Claims]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching PVC Data..." -ForegroundColor Yellow

    try {
        $pvcs = if ($null -ne $KubeData) {
            $KubeData.PersistentVolumeClaims.items
        } else {
            $raw = kubectl get pvc --all-namespaces -o json 2>&1 | Out-String
            if ($raw -match "No resources found") {
                Write-Host "`r🤖 ✅ No PVCs found in the cluster." -ForegroundColor Green
                if ($Json) { return @{ Total = 0; Items = @() } }
                if ($Text -and -not $Html) {
                    Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n✅ No PVCs found in the cluster."
                }
                if ($Html) { return "<p><strong>✅ No PVCs found in the cluster.</strong></p>" }
                if (-not $Text -and -not $Html -and -not $Json) {
                    Read-Host "🤖 Press Enter to return to the menu"
                }
                return
            }
            ($raw | ConvertFrom-Json).items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to retrieve PVC data: $_" -ForegroundColor Red
        if ($Json) { return @{ Error = "Failed to fetch PVC data"; Items = @() } }
        if ($Html) { return "<p><strong>❌ Failed to fetch PVC data.</strong></p>" }
        return
    }

    if ($ExcludeNamespaces) {
        $pvcs = Exclude-Namespaces -items $pvcs
    }

    if (-not $pvcs -or $pvcs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No PVCs found.   " -ForegroundColor Green
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Html) { return "<p><strong>✅ No PVCs found.</strong></p>" }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ PVCs fetched. (Total: $($pvcs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        $pods = if ($null -ne $KubeData) {
            $KubeData.Pods.items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch Pod data: $_" -ForegroundColor Red
        if ($Json) { return @{ Error = "Failed to fetch Pod data"; Items = @() } }
        if ($Html) { return "<p><strong>❌ Failed to fetch Pod data.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. (Total: $($pods.Count))" -ForegroundColor Green
    Write-Host "`n🤖 Analyzing PVC usage..." -ForegroundColor Yellow

    $attachedPVCs = $pods |
        ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } |
        Select-Object -ExpandProperty persistentVolumeClaim

    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }
    $totalPVCs = $unusedPVCs.Count

    if ($totalPVCs -eq 0) {
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No unused PVCs found.</strong></p>" }
        if ($Text -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n✅ No unused PVCs found."
        }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ PVC usage analyzed. ($totalPVCs unused PVCs detected)" -ForegroundColor Green

    $tableData = $unusedPVCs | ForEach-Object {
        [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            PVC       = $_.metadata.name
            Storage   = $_.spec.resources.requests.storage
        }
    }

    if ($Json) {
        return @{
            Total = $tableData.Count
            Items = $tableData
        }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, PVC, Storage |
            Out-String
        return "<p><strong>⚠️ Total Unused PVCs Found:</strong> $totalPVCs</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n⚠️ Total Unused PVCs Found: $totalPVCs"
        $tableString = $tableData | Format-Table Namespace, PVC, Storage -AutoSize | Out-Host | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPVCs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[💾 Unused Persistent Volume Claims - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 Persistent Volume Claims (PVCs) reserve storage in your cluster.",
                "",
                "📌 This check identifies PVCs that are NOT attached to any Pod.",
                "   - Unused PVCs may indicate abandoned or uncleaned storage.",
                "   - Storage resources remain allocated until PVCs are deleted.",
                "",
                "⚠️ Review unused PVCs before deletion to avoid accidental data loss.",
                "",
                "⚠️ Total Unused PVCs Found: $totalPVCs"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPVCs)

        $paged = $tableData[$startIndex..($endIndex - 1)]

        if ($paged) {
            $paged | Format-Table Namespace, PVC, Storage -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}