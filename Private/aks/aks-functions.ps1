function Invoke-AKSBestPractices {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [object]$KubeData
    )

    function Validate-Context {
        param ($ResourceGroup, $ClusterName)
        if ($KubeData) { return $true }

        $currentContext = kubectl config current-context
        $aksContext = az aks show --resource-group $ResourceGroup --name $ClusterName --query "name" -o tsv

        if ($Global:MakeReport) {
            Write-Host "🔄 Checking Kubernetes context..." -ForegroundColor Cyan
            Write-Host "   - Current context: '$currentContext'" -ForegroundColor Yellow
            Write-Host "   - Expected AKS cluster: '$aksContext'" -ForegroundColor Yellow

            if ($currentContext -eq $aksContext) {
                Write-Host "✅ Kubernetes context matches. Proceeding with the scan." -ForegroundColor Green
                return $true
            } else {
                Write-Host "⚠️ WARNING: Context mismatch." -ForegroundColor Red
                Write-ToReport "   - Skipping validation due to mismatched context."
                return $false
            }
        }

        $msg = @(
            "🔄 Checking your Kubernetes context...",
            "",
            "   - You're currently using context: '$currentContext'.",
            "   - The expected AKS cluster context is: '$aksContext'.",
            ""
        )

        if ($currentContext -eq $aksContext) {
            $msg += @("✅ The context is correct.")
            Write-SpeechBubble -msg $msg -color "Green" -icon "🤖"
            return $true
        } else {
            $msg += @(
                "⚠️ WARNING: Context mismatch!",
                "",
                "❌ Commands may target the wrong cluster.",
                "",
                "💡 Run: kubectl config use-context $aksContext"
            )
            Write-SpeechBubble -msg $msg -color "Yellow" -icon "🤖" -lastColor "Red"
            $confirmation = Read-Host "🤖 Continue anyway? (yes/no)"
            Clear-Host
            if ($confirmation -match "^(y|yes)$") {
                Write-SpeechBubble -msg @("⚠️ Proceeding despite mismatch...") -color "Yellow" -icon "🤖"
                return $true
            } else {
                Write-SpeechBubble -msg @("❌ Exiting to prevent incorrect execution.") -color "Red" -icon "🤖"
                exit 1
            }
        }
    }

    function Get-AKSClusterInfo {
        param (
            [string]$SubscriptionId,
            [string]$ResourceGroup,
            [string]$ClusterName
        )

        if ($KubeData) {
            return @{
                name      = $ClusterName
                KubeData  = $KubeData
                location  = "injected"
                kubernetesVersion = "mock"
            }
        }

        Write-Host -NoNewline "`n🤖 Fetching AKS cluster details..." -ForegroundColor Cyan
        $clusterInfo = az aks show --resource-group $ResourceGroup --name $ClusterName --output json | ConvertFrom-Json
        if (-not $clusterInfo) {
            Write-Host "❌ Failed to fetch cluster details." -ForegroundColor Red
            exit 1
        }

        Write-Host "🤖 Fetching Kubernetes constraint data..." -ForegroundColor Cyan
        $constraints = kubectl get constraints -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }

        return $clusterInfo
    }

    # Collect all checks
    $checks = @()
    Get-Variable -Name "*Checks" | ForEach-Object {
        $checks += $_.Value
    }
    $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }

    function Run-Checks {
        param ($clusterInfo)

        Write-Host "🤖 Running best practice checks..." -ForegroundColor Cyan
        if ($Global:MakeReport) {
            Write-ToReport "`n[✅ AKS Best Practices Check]`n"
        }

        $categories = @{
            "Security"             = @();
            "Networking"           = @();
            "Resource Management"  = @();
            "Monitoring & Logging" = @();
            "Identity & Access"    = @();
            "Disaster Recovery"    = @();
            "Best Practices"       = @();
        }

        if (-not $Global:MakeReport) { Clear-Host }

        foreach ($check in $checks) {
            try {
                $value = if ($check.Value -is [scriptblock]) {
                    & $check.Value
                } elseif ($check.Value -match "^(True|False|[0-9]+)$") {
                    [bool]([System.Convert]::ChangeType($check.Value, [boolean]))
                } else {
                    Invoke-Expression ($check.Value -replace '\$clusterInfo', '$clusterInfo')
                }

                $result = if ($value -eq $check.Expected) { "✅ PASS" } else { "❌ FAIL" }

                $categories[$check.Category] += [PSCustomObject]@{
                    ID             = $check.ID;
                    Check          = $check.Name;
                    Severity       = $check.Severity;
                    Category       = $check.Category;
                    Status         = $result;
                    Recommendation = if ($result -eq "✅ PASS") { "$($check.Name) is enabled." } else { $check.FailMessage }
                    URL            = $check.URL
                }

                if ($Global:MakeReport) {
                    Write-ToReport "[$($check.Category)] $($check.Name) - $result"
                    Write-ToReport "   🔹 Severity: $($check.Severity)"
                    Write-ToReport "   🔹 Recommendation: $($categories[$check.Category][-1].Recommendation)"
                    Write-ToReport "   🔹 Info: $($check.URL)`n"
                }
            }
            catch {
                Write-Host "Error processing check: $($check.Name). $_" -ForegroundColor Red
            }
        }

        return $categories
    }

    # Reuse Display-Results with no changes

    # Main Execution Flow
    if ($Global:MakeReport) {
        Write-Host "`n🤖 Starting AKS Best Practices Check...`n" -ForegroundColor Green
    }

    Validate-Context -ResourceGroup $ResourceGroup -ClusterName $ClusterName
    $clusterInfo = Get-AKSClusterInfo -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
    $checkResults = Run-Checks -clusterInfo $clusterInfo

    if ($Html) {
        return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html
    } else {
        Display-Results -categories $checkResults -FailedOnly:$FailedOnly
        if (-not $Global:MakeReport) {
            Write-Host "`nPress Enter to return to the menu..." -ForegroundColor Yellow
            Read-Host
        }
    }

    if ($Global:MakeReport) {
        Write-Host "`n✅ AKS Best Practices Check Completed.`n" -ForegroundColor Green
    }
}
