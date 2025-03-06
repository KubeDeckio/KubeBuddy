function Show-EmptyNamespaces {
    param(
        [int]$PageSize = 10, # Number of namespaces per page
        [switch]$Html        # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📂 Empty Namespaces]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Namespace Data..." -ForegroundColor Yellow

    # Fetch all namespaces
    $namespaces = kubectl get namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Select-Object -ExpandProperty metadata |
    Select-Object -ExpandProperty name

    # Fetch all pods and their namespaces
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Group-Object { $_.metadata.namespace }

    # Extract namespaces that have at least one pod
    $namespacesWithPods = $pods.Name

    # Get only namespaces that are completely empty
    $emptyNamespaces = $namespaces | Where-Object { $_ -notin $namespacesWithPods }

    $totalNamespaces = $emptyNamespaces.Count

    if ($totalNamespaces -eq 0) {
        Write-Host "`r🤖 ✅ No empty namespaces found." -ForegroundColor Green

        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[📂 Empty Namespaces]`n"
            Write-ToReport "✅ No empty namespaces found."
        }

        # If not in report mode or HTML mode, prompt to continue
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No empty namespaces found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Namespaces fetched. ($totalNamespaces empty namespaces detected)" -ForegroundColor Green

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
    if ($Global:MakeReport) {
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

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $namespace = $emptyNamespaces[$i]
            $tableData += [PSCustomObject]@{ "Namespace" = $namespace }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace -AutoSize
        }

        # Pagination
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}