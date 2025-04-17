function Show-YamlCheckInteractive {
    param (
        [string[]]$CheckIDs,
        [switch]$ExcludeNamespaces,
        [int]$PageSize = 10
    )

    $result = Invoke-yamlChecks -CheckIDs $CheckIDs -ExcludeNamespaces:$ExcludeNamespaces
    $checks = $result.Items

    if (-not $checks -or $checks.Count -eq 0) {
        Write-Host "`n🤖 No checks returned any data." -ForegroundColor Yellow
        Read-Host "`n🤖 Press Enter to return"
        return
    }

    foreach ($check in $checks) {
        Clear-Host

        $speechMsg = @()

        if ($check.Recommendation -is [hashtable] -and $check.Recommendation.SpeechBubble) {
            $speechMsg = $check.Recommendation.SpeechBubble
        }
        else {
            $recommendationText = if ($check.Recommendation -is [string]) {
                $check.Recommendation
            }
            elseif ($check.Recommendation.text) {
                $check.Recommendation.text
            }
            else {
                ""
            }

            $speechMsg = @(
                "🤖 $($check.Name)",
                "",
                "📌 $($check.Description)",
                "",
                "📎 Recommendation:",
                $recommendationText
            )
        }

        Write-Host "`n[$($check.ID)] $($check.Name)" -ForegroundColor Cyan
        Write-Host "----------------------------------"
        # Write-Host "⚠️ Total Issues: $($check.Total)" -ForegroundColor Yellow

        $items = $check.Items
        if (-not $items -or $items.Count -eq 0) {
            Write-Host "✅ No issues found." -ForegroundColor Green
            Read-Host "`n🤖 Press Enter to continue"
            continue
        }

        $validProps = $items | ForEach-Object { $_.PSObject.Properties.Name } |
            Group-Object | Sort-Object Count -Descending |
            Select-Object -ExpandProperty Name -Unique

        if (-not $validProps) {
            Write-Host "No valid properties to show." -ForegroundColor DarkGray
            Read-Host "`n🤖 Press Enter to continue"
            continue
        }

        Write-SpeechBubble -msg $speechMsg -color "Cyan" -icon "🤖" -lastColor "Yellow" -delay 30

        $totalItems = $items.Count
        $totalPages = [math]::Ceiling($totalItems / $PageSize)
        $currentPage = 0

        do {
            Write-Host "`n[$($check.ID)] $($check.Name) - Page $($currentPage + 1) of $totalPages" -ForegroundColor Cyan
            Write-Host "----------------------------------"

            $startIndex = $currentPage * $PageSize
            $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

            $pagedItems = $items[$startIndex..($endIndex - 1)]
            $pagedItems | Format-Table -Property $validProps -AutoSize | Out-Host

            $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
            if ($newPage -eq -1) { break }
            $currentPage = $newPage
        } while ($true)

        Read-Host "`n🤖 Press Enter to continue"
    }
}
