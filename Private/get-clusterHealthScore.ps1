# function Get-ClusterHealthScore {
#     param (
#         [array]$Checks
#     )

#     $validChecks = $Checks | Where-Object {
#         $_.Weight -ne $null -and $_.Total -ne $null
#     }


#     if (-not $validChecks) {
#         Write-Host "⚠️ No valid checks found." -ForegroundColor Red
#         return 0
#     }

#     $maxScore = ($validChecks | Measure-Object -Property Weight -Sum).Sum
#     $earnedScore = ($validChecks | Where-Object { $_.Total -eq 0 } | Measure-Object -Property Weight -Sum).Sum

#     $score = [math]::Round(($earnedScore / $maxScore) * 100)
#     return $score
# }

# function Get-ClusterHealthScore {
#     param (
#         [array]$Checks
#     )

#     # only keep checks that declare a weight and have a Total count
#     $validChecks = $Checks | Where-Object { $_.Weight -ne $null -and $_.Total -ne $null }

#     # total possible weight sum
#     $maxScore = ($validChecks | Measure-Object Weight -Sum).Sum

#     # compute earned score contribution per check with diminishing returns:
#     # contribution = Weight * (1 - Total/(Total+1)) = Weight/(Total+1)
#     $earnedScore = 0
#     foreach ($chk in $validChecks) {
#         $t = [int]$chk.Total
#         $w = [double]$chk.Weight
#         $earnedScore += $w * (1 - ($t / ($t + 1)))
#     }

#     # final percentage score
#     if ($maxScore -gt 0) {
#         return [math]::Round(($earnedScore / $maxScore) * 100)
#     }
#     else {
#         return 0
#     }
# }

function Get-ClusterHealthScore {
    param (
        [array]$Checks
    )

    # map severities to numeric weights (case-insensitive keys)
    $severityWeights = @{
        'critical' = 3
        'warning'  = 2
        'info'     = 1
    }

    # include checks with Weight and either Findings or Total count
    $validChecks = $Checks | Where-Object { $_.Weight -ne $null -and ($_.Findings -ne $null -or $_.Total -ne $null) }

    # total possible weight
    $maxWeight = ($validChecks | Measure-Object Weight -Sum).Sum

    # compute earned score with severity-based diminishing returns
    $earned = 0.0
    foreach ($chk in $validChecks) {
        # determine severity sum: use Findings if present, else use Total as count of Info-level issues
        if ($null -ne $chk.Findings) {
            $sevSum = ($chk.Findings | ForEach-Object {
                $sevKey = $_.Severity?.ToString().ToLower()
                if ($sevKey -and $severityWeights.ContainsKey($sevKey)) {
                    $severityWeights[$sevKey]
                } else {
                    $severityWeights['info']
                }
            } | Measure-Object -Sum).Sum
        }
        else {
            # treat each total count as Info-level issues
            $sevSum = [int]$chk.Total
        }

        # each check contributes Weight/(SeveritySum+1)
        $earned += ($chk.Weight / ($sevSum + 1))
    }

    # final score as percentage of max possible
    if ($maxWeight -gt 0) {
        return [math]::Round(($earned / $maxWeight) * 100)
    }
    else {
        return 0
    }
}
