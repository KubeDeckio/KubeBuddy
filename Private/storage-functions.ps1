function Show-UnusedPVCs {
    param(
        [int]$PageSize = 10,
        [switch]$Html,  # If specified, return an HTML table
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[💾 Unused Persistent Volume Claims]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching PVC Data..." -ForegroundColor Yellow

    # Capture raw kubectl output
    $pvcsRaw = kubectl get pvc --all-namespaces -o json 2>&1 | Out-String

    # "No resources found" before JSON parse
    if ($pvcsRaw -match "No resources found") {
        Write-Host "`r🤖 ✅ No PVCs found in the cluster." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No PVCs found in the cluster."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No PVCs found in the cluster.</strong></p>" }
        return
    }

    if ($ExcludeNamespaces) {
        $pvcsRaw = Exclude-Namespaces -items $pvcsRaw
    }
    

    # Convert JSON
    try {
        $pvcsJson = $pvcsRaw | ConvertFrom-Json
        $pvcs = if ($pvcsJson.PSObject.Properties['items']) { $pvcsJson.items } else { @() }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to parse JSON from kubectl output." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "❌ Failed to parse JSON from kubectl output."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Failed to parse JSON from kubectl output.</strong></p>" }
        return
    }

    # Ensure array
    if ($pvcs -isnot [System.Array]) { $pvcs = @($pvcs) }

    # Check if PVCs exist
    if ($pvcs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No unused PVCs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No unused PVCs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ PVCs fetched. (Total: $($pvcs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    # Fetch all Pods
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    if (-not $pods) {
        Write-Host "`r🤖 ❌ Failed to fetch Pod data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "❌ Failed to fetch Pod data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Failed to fetch Pod data.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. (Total: $($pods.Count))" -ForegroundColor Green

    Write-Host "`n🤖 Analyzing PVC usage..." -ForegroundColor Yellow

    # Gather attached PVCs from pod volumes
    $attachedPVCs = $pods |
    ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } |
    Select-Object -ExpandProperty persistentVolumeClaim

    # Filter out any that appear in attachedPVCs
    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }
    $totalPVCs = $unusedPVCs.Count

    if ($totalPVCs -eq 0) {
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No unused PVCs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No unused PVCs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ PVC usage analyzed. ($totalPVCs unused PVCs detected)" -ForegroundColor Green

    # If -Html, return an HTML table
    if ($Html) {
        $tableData = foreach ($pvc in $unusedPVCs) {
            [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        $htmlTable = $tableData |
        ConvertTo-Html -Fragment -Property Namespace, PVC, Storage -PreContent "<h2>Unused Persistent Volume Claims</h2>" |
        Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Unused PVCs Found:</strong> $totalPVCs</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html)
    if ($Global:MakeReport) {
        Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
        Write-ToReport "⚠️ Total Unused PVCs Found: $totalPVCs"
        Write-ToReport "-------------------------------------------------"

        $tableData = @()
        foreach ($pvc in $unusedPVCs) {
            $tableData += [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        $tableString = $tableData | Format-Table Namespace, PVC, Storage -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPVCs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[💾 Unused Persistent Volume Claims - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 Persistent Volume Claims (PVCs) reserve storage in your cluster.",
            "",
            "📌 This check identifies PVCs that are NOT attached to any Pod.",
            "   - Unused PVCs may indicate abandoned or uncleaned storage.",
            "   - Storage resources remain allocated until PVCs are deleted.",
            "",
            "⚠️ Review unused PVCs before deletion to avoid accidental data loss.",
            "",
            "⚠️ Total Unused PVCs Found: $totalPVCs"
        )
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPVCs)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pvc = $unusedPVCs[$i]
            $tableData += [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, PVC, Storage -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}