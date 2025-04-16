function Get-ClusterHealthScore {
    param (
        [array]$Checks
    )

    $totalWeight = 0
    $failedWeight = 0

    foreach ($check in $Checks) {
        $weight = $check.Weight
        if (-not $weight) { continue }

        $totalWeight += $weight
        if ($check.Status -ne 'Passed') {
            $failedWeight += $weight
        }
    }

    if ($totalWeight -eq 0) { return 0 }

    $score = 100 - (($failedWeight / $totalWeight) * 100)
    return [math]::Round($score, 1)
}
