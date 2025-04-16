function Get-ClusterHealthScore {
    param (
        [array]$Checks
    )

    $validChecks = $Checks | Where-Object {
        $_.Weight -ne $null -and $_.Total -ne $null
    }


    if (-not $validChecks) {
        Write-Host "⚠️ No valid checks found." -ForegroundColor Red
        return 0
    }

    $maxScore = ($validChecks | Measure-Object -Property Weight -Sum).Sum
    $earnedScore = ($validChecks | Where-Object { $_.Total -eq 0 } | Measure-Object -Property Weight -Sum).Sum

    $score = [math]::Round(($earnedScore / $maxScore) * 100)
    return $score
}
