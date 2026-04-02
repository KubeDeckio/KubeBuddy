function Create-CsvReport {
    param (
        [string]$OutputPath,
        [object]$KubeData,
        [switch]$ExcludeNamespaces,
        [switch]$Aks,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName
    )

    # Strip all newlines and extra whitespace from a string value
    filter Format-CsvValue {
        ([string]$_) -replace '[\r\n]+', ' ' -replace '[^\x00-\x7F\u00C0-\u024F]', '' -replace '\s{2,}', ' ' | ForEach-Object { $_.Trim() }
    }

    # Run YAML-based checks
    $yamlCheckResults = Invoke-yamlChecks -Json -KubeData $KubeData -ExcludeNamespaces:$ExcludeNamespaces

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($check in $yamlCheckResults.Items) {
        if (-not $check.ID) { continue }

        $status = if ($check.Error) {
            "ERROR"
        } elseif ($check.Total -gt 0) {
            "FAIL"
        } else {
            "PASS"
        }

        $recommendation = if ($check.Recommendation -is [hashtable] -or $check.Recommendation -is [System.Collections.Hashtable]) {
            $check.Recommendation.text | Format-CsvValue
        } else {
            $check.Recommendation | Format-CsvValue
        }

        $checkId       = $check.ID       | Format-CsvValue
        $checkName     = $check.Name     | Format-CsvValue
        $checkCategory = $check.Category | Format-CsvValue
        $checkSeverity = $check.Severity | Format-CsvValue
        $checkUrl      = $check.URL      | Format-CsvValue

        if ($status -eq "FAIL" -and $check.Items -and $check.Items.Count -gt 0) {
            foreach ($item in $check.Items) {
                $parts = @()
                if ($item.Namespace) { $parts += $item.Namespace | Format-CsvValue }
                if ($item.Resource)  { $parts += $item.Resource  | Format-CsvValue }
                if ($item.Message)   { $parts += $item.Message   | Format-CsvValue }
                elseif ($item.Issue) { $parts += $item.Issue     | Format-CsvValue }

                $rows.Add([PSCustomObject]@{
                    ID             = $checkId
                    Name           = $checkName
                    Category       = $checkCategory
                    Severity       = $checkSeverity
                    Status         = $status
                    Message        = $parts -join " | "
                    Recommendation = $recommendation
                    URL            = $checkUrl
                })
            }
        } else {
            $message = if ($check.Message) {
                $check.Message | Format-CsvValue
            } elseif ($check.SummaryMessage) {
                $check.SummaryMessage | Format-CsvValue
            } elseif ($check.Error) {
                $check.Error | Format-CsvValue
            } else {
                ""
            }

            $rows.Add([PSCustomObject]@{
                ID             = $checkId
                Name           = $checkName
                Category       = $checkCategory
                Severity       = $checkSeverity
                Status         = $status
                Message        = $message
                Recommendation = $recommendation
                URL            = $checkUrl
            })
        }
    }

    # AKS-specific checks
    if ($Aks) {
        try {
            $aksCheckResults = Invoke-AKSBestPractices -Json -KubeData $KubeData -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName

            if ($aksCheckResults -and $aksCheckResults.Items) {
                foreach ($check in $aksCheckResults.Items) {
                    if (-not $check.ID) { continue }

                    $rawStatus = [string]$check.Status
                    $status = if ($rawStatus -match "PASS") { "PASS" }
                              elseif ($rawStatus -match "ERROR") { "ERROR" }
                              elseif ($rawStatus -match "FAIL") { "FAIL" }
                              else { $rawStatus }

                    $message = if ($check.FailMessage) {
                        $check.FailMessage | Format-CsvValue
                    } else {
                        $check.ObservedValue | Format-CsvValue
                    }

                    $recommendation = if ($check.Recommendation -is [hashtable] -or $check.Recommendation -is [System.Collections.Hashtable]) {
                        $check.Recommendation.text | Format-CsvValue
                    } else {
                        $check.Recommendation | Format-CsvValue
                    }

                    $rows.Add([PSCustomObject]@{
                        ID             = $check.ID       | Format-CsvValue
                        Name           = $check.Name     | Format-CsvValue
                        Category       = $check.Category | Format-CsvValue
                        Severity       = $check.Severity | Format-CsvValue
                        Status         = $status
                        Message        = $message
                        Recommendation = $recommendation
                        URL            = $check.URL      | Format-CsvValue
                    })
                }
            }
        }
        catch {
            Write-Warning "Failed to run AKS best practices for CSV report: $_"
        }
    }

    $csv = $rows | ConvertTo-Csv -NoTypeInformation
    [System.IO.File]::WriteAllLines($OutputPath, $csv, [System.Text.UTF8Encoding]::new($true))
}
