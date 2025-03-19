# Main Script: AKS Best Practices Checklist
function Invoke-AKSBestPractices {
    param (
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$html
    )

    # Authenticate with Azure and fetch cluster details
    function Authenticate {
        Write-Host "🤖 Authenticating with Azure..." -ForegroundColor Cyan
        az login --use-device-code --output none
        az account set --subscription $SubscriptionId
        if ($?) {
            Write-Host "🤖 Authentication successful." -ForegroundColor Green
        }
        else {
            Write-Host "🤖 Authentication failed. Exiting..." -ForegroundColor Red
            exit 1
        }
    }

    function Validate-Context {
        param (
            [string]$ResourceGroup,
            [string]$ClusterName
        )
    
        # Get the current Kubernetes context
        $currentContext = kubectl config current-context
    
        # Get the AKS cluster details and extract the correct context
        $aksContext = az aks show --resource-group $ResourceGroup --name $ClusterName --query "name" -o tsv
    
        # If report mode is enabled, log the context check but don’t print anything to CLI
        if ($Global:MakeReport) {
            Write-Host "🔄 Checking Kubernetes context..." -ForegroundColor Cyan
            Write-Host "   - Current context: '$currentContext'" -ForegroundColor Yellow
            Write-Host "   - Expected AKS cluster: '$aksContext'" -ForegroundColor Yellow
    
            if ($currentContext -eq $aksContext) {
                Write-Host "✅ Kubernetes context matches. Proceeding with the scan." -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "⚠️ WARNING: The current Kubernetes context ('$currentContext') does NOT match the expected AKS cluster ('$aksContext')." -ForegroundColor Red
                Write-ToReport "   - Cluster validation skipped due to mismatched context."
                return $false  # Skip cluster validation in report mode but continue execution
            }
        }
    
        # Speech bubble message for CLI output (only if not in report mode)
        $msg = @(
            "🔄 Checking your Kubernetes context...",
            "",
            "   - You're currently using context: '$currentContext'.",
            "   - The expected AKS cluster context is: '$aksContext'.",
            ""
        )
    
        if ($currentContext -eq $aksContext) {
            $msg += @("✅ The context is correct. Proceeding with the scan.")
            Write-SpeechBubble -msg $msg -color "Green" -icon "🤖"
            return $true
        }
        else {
            $msg += @(
                "⚠️ WARNING: The current Kubernetes context does NOT match the AKS cluster!",
                "",
                "❌ Running commands in the wrong context may impact the wrong cluster!",
                "",
                "💡 To set the correct context, run the following command:",
                "   kubectl config use-context $aksContext",
                "",
                "Then re-run this script."
            )
    
            Write-SpeechBubble -msg $msg -color "Yellow" -icon "🤖" -lastColor "Red"
    
            $confirmation = Read-Host "🤖 Do you want to continue anyway? (yes/no)"
            
            Clear-Host
    
            if ($confirmation -match "^(y|yes)$") {
                $msg = @("⚠️ Proceeding with mismatched context...")
                Write-SpeechBubble -msg $msg -color "Yellow" -icon "🤖"
                return $true
            }
            else {
                $msg = @(
                    "❌ Exiting to prevent incorrect cluster impact.",
                    "",
                    "💡 Run the following command to switch to the correct AKS context:",
                    "   kubectl config use-context $aksContext",
                    "",
                    "Once the correct context is set, you can rerun this script."
                )
                Write-SpeechBubble -msg $msg -color "Red" -icon "🤖"
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
        Write-Host -no "`n🤖 Fetching AKS cluster details..." -ForegroundColor Cyan
        $clusterInfo = az aks show --resource-group $ResourceGroup --name $ClusterName --output json | ConvertFrom-Json
        if (-not $clusterInfo) {
            Write-Host "🤖 Error: Failed to fetch cluster details. Exiting..." -ForegroundColor Red
            exit 1
        }

        # Fetch Kubernetes constraint data in a single command
        Write-Host "🤖 Fetching Kubernetes constraint data..." -ForegroundColor Cyan
        $kubeData = @{
            Constraints = kubectl get constraints -A -o json | ConvertFrom-Json
        }

        # Attach KubeData to clusterInfo
        $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value $kubeData

        return $clusterInfo
    }

    # Combine all checks from variables ending with 'Checks'
    $checks = @()
    Get-Variable -Name "*Checks" | ForEach-Object {
        $checks += $_.Value
    }

    # Remove duplicate checks based on their ID
    $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }

    function Run-Checks {
        param (
            $clusterInfo
        )

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

        if (-not $Global:MakeReport) {
        Clear-Host
    }

        foreach ($check in $checks) {
            try {
                # Write-Host "Evaluating Check: $($check.Name)"
                # Write-Host "Expression: $($check.Value)"

                # If the check is stored as a ScriptBlock, execute it
                if ($check.Value -is [scriptblock]) {
                    $value = & $check.Value
                }
                else {
                    # Fix: Ensure we only evaluate valid PowerShell expressions
                    if ($check.Value -match "^(True|False|[0-9]+)$") {
                        $value = [bool]([System.Convert]::ChangeType($check.Value, [boolean]))
                    }
                    else {
                        $value = Invoke-Expression ($check.Value -replace '\$clusterInfo', '$clusterInfo')
                    }
                }


                # Write-Host "Evaluated Value: $value"
                # Write-Host "Expected Value: $($check.Expected)"

                if ($value -eq $check.Expected) {
                    $categories[$check.Category] += [PSCustomObject]@{
                        ID             = $check.ID;
                        Check          = $check.Name;
                        Severity       = $check.Severity;
                        Category       = $check.Category;
                        Status         = "✅ PASS";
                        Recommendation = "$($check.Name) is enabled.";
                        URL            = $check.URL
                    }
                }
                else {
                    $categories[$check.Category] += [PSCustomObject]@{
                        ID             = $check.ID;
                        Check          = $check.Name;
                        Severity       = $check.Severity;
                        Category       = $check.Category;
                        Status         = "❌ FAIL";
                        Recommendation = $check.FailMessage
                        URL            = $check.URL
                    }
                }

                # Log to text report
                if ($Global:MakeReport) {
                    Write-ToReport "[$($check.Category)] $($check.Name) - Status: $($categories[$check.Category][-1].Status)"
                    Write-ToReport "   🔹 Severity: $($check.Severity)"
                    Write-ToReport "   🔹 Recommendation: $($categories[$check.Category][-1].Recommendation)"
                    Write-ToReport "   🔹 More Info: $($check.URL)`n"
                }

            }
            catch {
                Write-Host "Error processing check: $($check.Name). Skipping... $_" -ForegroundColor Red
            }
        }
        return $categories
    }

    function Display-Results {
        param (
            [hashtable]$categories,
            [switch]$FailedOnly,
            [switch]$Html
        )
    
        $passCount = 0
        $failCount = 0
        $reportData = @()  # ✅ Initialize empty array to prevent null reference
    
        foreach ($category in $categories.Keys) {
            # Filter checks if -FailedOnly is specified
            $checks = $categories[$category]
            if ($FailedOnly) {
                $checks = $checks | Where-Object { $_.Status -eq "❌ FAIL" }
            }
    
            if ($checks.Count -gt 0 -and -not $Html -and -not $Global:MakeReport) {
                Write-Host "`n=== $category ===             " -ForegroundColor Cyan
                $checks | Format-Table ID, Check, Severity, Category, Status, Recommendation, URL -AutoSize
    
                # ✅ Show "Press any key to continue..." message
                Write-Host "`nPress any key to continue..." -ForegroundColor Magenta -NoNewline
    
                # ✅ Wait for keypress
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
                # ✅ Move cursor up one line and clear it
                if ($Host.Name -match "ConsoleHost") {
                    # Windows Terminal / Standard PowerShell console
                    [Console]::SetCursorPosition(0, [Console]::CursorTop - 1)
                    Write-Host (" " * 50) -NoNewline
                    [Console]::SetCursorPosition(0, [Console]::CursorTop)
                }
                else {
                    # ANSI escape codes for clearing a line (Linux/macOS)
                    Write-Host "`e[1A`e[2K" -NoNewline
                }
            }
            else {
                # ✅ Append check results to $reportData
                $reportData += $checks | Select-Object ID, Check, Severity, Category, Status, Recommendation, URL
            }
    
            # Count passed and failed checks
            $passCount += ($categories[$category] | Where-Object { $_.Status -eq "✅ PASS" }).Count
            $failCount += ($categories[$category] | Where-Object { $_.Status -eq "❌ FAIL" }).Count
        }
    
        # **Summary Calculation**
        $total = $passCount + $failCount
        $score = if ($total -eq 0) { 0 } else { [math]::Round(($passCount / $total) * 100, 2) }
    
        # **Fix: Pick only the first rating letter**
        $rating = @(switch ($score) {
                { $_ -ge 90 } { "A" }
                { $_ -ge 80 } { "B" }
                { $_ -ge 70 } { "C" }
                { $_ -ge 60 } { "D" }
                default { "F" }
            })[0]  # Picks only the FIRST rating letter
    
        # **Assign Color for Rating**
        $ratingColor = switch ($rating) {
            "A" { "Green" }
            "B" { "Yellow" }
            "C" { "DarkYellow" }
            "D" { "Red" }
            "F" { "DarkRed" }
            default { "Gray" }
        }
    
        # **CLI Output for Summary**
        if (-not $Html -and -not $Global:MakeReport) {
            Write-Host "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-Host $header -ForegroundColor Cyan
            Write-Host $separator -ForegroundColor Cyan
            Write-Host "$row " -NoNewline
            Write-Host "$rating" -ForegroundColor $ratingColor # Rating is colored correctly
        }

        if ($global:MakeReport) {
            Write-ToReport "`nSummary & Rating:           " -ForegroundColor Green
    
            $header = "{0,-12} {1,-12} {2,-12} {3,-12} {4,-8}" -f "Passed", "Failed", "Total", "Score (%)", "Rating"
            $separator = "============================================================"
            $row = "{0,-12} {1,-12} {2,-12} {3,-12}" -f "✅ $passCount", "❌ $failCount", "$total", "$score"
    
            Write-ToReport $header
            Write-ToReport $separator
            Write-ToReport "$row " -NoNewline
            Write-ToReport "$rating"
        }
    
        # ✅ **HTML Output: Return Key Values**
        if ($Html) {
            $htmlTable = if ($reportData.Count -gt 0) {
                $sortedReportData = $reportData | Sort-Object @{Expression = { $_.Status -eq "❌ FAIL" } ; Descending = $true }, Category
                $sortedReportData | ConvertTo-Html -Fragment -Property ID, Check, Severity, Category, Status, Recommendation, URL | Out-String
            }
            else {
                "<p><strong>No best practice violations detected.</strong></p>"
            }
    
            return [PSCustomObject]@{
                Passed = $passCount
                Failed = $failCount
                Total  = $total
                Score  = $score
                Rating = "$rating"
                Data   = $htmlTable
            }
        }
    }
    
    # Main Execution
    # ✅ Execute the checks
    if ($Global:MakeReport) {
        Write-Host "`n🤖 Starting AKS Best Practices Check...`n" -ForegroundColor Green
    }

    #Authenticate
    Validate-Context -ResourceGroup $ResourceGroup -ClusterName $ClusterName
    $clusterInfo = Get-AKSClusterInfo -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName

    $checkResults = Run-Checks -clusterInfo $clusterInfo
    if ($html) {
        # Capture HTML output and return it
        $htmlContent = Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html
        return $htmlContent
    }
    else {
        # Display results in console
        Display-Results -categories $checkResults -FailedOnly:$FailedOnly
        # ✅ Keep the script open until the user presses Enter
        If (-not $Global:MakeReport) {
            Write-Host "`nPress Enter to return to the menu..." -ForegroundColor Yellow
            Read-Host
        }
    }
    # ✅ Close the report when done
    if ($Global:MakeReport) {
        Write-Host "`n✅ AKS Best Practices Check Completed.`n" -ForegroundColor Green
    }
}