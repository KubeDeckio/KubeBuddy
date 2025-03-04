function Generate-K8sHTMLReport {
    param (
        [string]$outputPath
    )

    # Load kubebuddy.ps1
    $kubebuddyScript = "$pwd/kubebuddy.ps1"
    if (Test-Path $kubebuddyScript) {
        . $kubebuddyScript
        Write-Host "✅ Loaded kubebuddy.ps1 successfully."
    } else {
        Write-Host "⚠️ Warning: kubebuddy.ps1 not found. Ensure it's in the correct directory." -ForegroundColor Yellow
        return
    }

    # Ensure output file is cleared before writing
    if (Test-Path $outputPath) {
        Remove-Item $outputPath -Force
    }

    # Capture console output while still displaying it
    Write-Host "🔄 Running Show-ClusterSummary..."
    $clusterSummaryRaw = Show-ClusterSummary *>&1  # Captures output while displaying it

    # Convert output array to a single string
    $clusterSummaryText = $clusterSummaryRaw -join "`n"

    # Debugging: Print the exact raw captured output
    Write-Host "🔍 Full Cluster Summary Output:"
    Write-Host $clusterSummaryText

    # Function to extract numerical values correctly
    function Extract-Metric($label, $data) {
        if ($data -match "$label\s*:\s*([\d]+)") {
            return $matches[1]
        }
        return "0"
    }

    # Extract Cluster Name and Kubernetes Version properly
    $clusterName = "Unknown"
    $k8sVersion  = "Unknown"

    # Read line by line for better extraction
    for ($i = 0; $i -lt $clusterSummaryRaw.Count; $i++) {
        $line = [string]$clusterSummaryRaw[$i] -replace "`r", "" -replace "`n", ""

        # Cluster Name is 2 lines below "Cluster Name"
        if ($line -match "Cluster Name\s*$") {
            $clusterName = [string]$clusterSummaryRaw[$i + 2] -replace "`r", "" -replace "`n", ""
        }

        # Kubernetes Version is 2 lines below "Kubernetes Version"
        if ($line -match "Kubernetes Version\s*$") {
            $k8sVersion = [string]$clusterSummaryRaw[$i + 2] -replace "`r", "" -replace "`n", ""
        }
    }

    # Extract Compatibility Check
    $compatibilityCheck = if ($clusterSummaryText -match "⚠️\s+(Cluster is running an outdated version:[^\n]+)") {
        $matches[1].Trim()
    }
    else {
        "Unknown"
    }

    # Extract numerical data with improved regex
    $totalNodes    = Extract-Metric "🚀 Nodes"         $clusterSummaryText
    $healthyNodes  = Extract-Metric "🟩 Healthy"       $clusterSummaryText
    $issueNodes    = Extract-Metric "🟥 Issues"        $clusterSummaryText
    $totalPods     = Extract-Metric "📦 Pods"          $clusterSummaryText
    $runningPods   = Extract-Metric "🟩 Running"       $clusterSummaryText
    $failedPods    = Extract-Metric "🟥 Failed"        $clusterSummaryText
    $totalRestarts = Extract-Metric "🔄 Restarts"      $clusterSummaryText
    $warnings      = Extract-Metric "🟨 Warnings"      $clusterSummaryText
    $critical      = Extract-Metric "🟥 Critical"      $clusterSummaryText
    $pendingPods   = Extract-Metric "⏳ Pending Pods"   $clusterSummaryText
    $stuckPods     = Extract-Metric "⚠️ Stuck Pods"    $clusterSummaryText
    $jobFailures   = Extract-Metric "📉 Job Failures"  $clusterSummaryText

    # Extract Pod Distribution
    $podAvg = if ($clusterSummaryText -match "📊 Pod Distribution: Avg: ([\d.]+)") { $matches[1] } else { "0" }
    $podMax = if ($clusterSummaryText -match "Max: ([\d.]+)") { $matches[1] } else { "0" }
    $podMin = if ($clusterSummaryText -match "Min: ([\d.]+)") { $matches[1] } else { "0" }
    $podTotalNodes = if ($clusterSummaryText -match "Total Nodes: ([\d]+)") { $matches[1] } else { "0" }

    # Extract CPU and Memory Usage
    $cpuUsage = if ($clusterSummaryText -match "🖥  CPU Usage:\s*([\d.]+)%") { $matches[1] } else { "0" }
    $cpuStatus = if ($clusterSummaryText -match "🖥  CPU Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }

    $memUsage = if ($clusterSummaryText -match "💾 Memory Usage:\s*([\d.]+)%") { $matches[1] } else { "0" }
    $memStatus = if ($clusterSummaryText -match "💾 Memory Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }

    # Debugging: Print extracted values
    Write-Host "📊 Extracted Values:"
    Write-Host "Cluster Name: $clusterName"
    Write-Host "Kubernetes Version: $k8sVersion"
    Write-Host "Compatibility: $compatibilityCheck"
    Write-Host "Nodes: $totalNodes, Healthy: $healthyNodes, Issues: $issueNodes"
    Write-Host "Pods: $totalPods, Running: $runningPods, Failed: $failedPods"
    Write-Host "Restarts: $totalRestarts, Warnings: $warnings, Critical: $critical"
    Write-Host "Pending Pods: $pendingPods, Stuck Pods: $stuckPods, Job Failures: $jobFailures"
    Write-Host "Pod Distribution -> Avg: $podAvg, Max: $podMax, Min: $podMin, Total Nodes: $podTotalNodes"
    Write-Host "CPU Usage: $cpuUsage%, Status: $cpuStatus"
    Write-Host "Memory Usage: $memUsage%, Status: $memStatus"

    # Prepare the dynamic date
    $today = (Get-Date -Format "MMMM dd, yyyy")

    # Build the HTML Template
    $htmlTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kubernetes Cluster Report</title>
<style>
    body { 
        font-family: Arial, sans-serif; 
        margin: 0; 
        padding: 0; 
        background: #eceff1; 
        color: #37474f; 
    }
    .header { 
        background-color: #0071FF; 
        color: white; 
        display: flex; 
        justify-content: space-between; 
        align-items: flex-start; 
        padding: 20px;
        font-weight: bold;
        font-size: 24px;
    }
    .container { 
        max-width: 1000px; 
        margin: 20px auto; 
        background: white; 
        padding: 20px; 
        border-radius: 8px; 
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2); 
    }
    .compatibility { 
        padding: 12px; 
        border-radius: 5px; 
        background: #ffeb3b; 
        font-weight: bold; 
        color: #f57f17; 
        text-align: center; 
    }
    table { 
        width: 100%; 
        border-collapse: collapse; 
        margin: 20px 0; 
        font-size: 14px; 
        text-align: left; 
    }
    table, th, td { 
        border: 1px solid #cfd8dc; 
        padding: 12px; 
    }
    th { 
        background-color: #1e88e5; 
        color: white; 
    }
</style>
</head>
<body>
<div class="header">
  <div style="display: flex; flex-direction: column;">
    <span>Kubernetes Cluster Report: $clusterName</span>
    <span style="font-size: 18px;">Powered by <strong>KubeBuddy</strong></span>
  </div>

  <!-- Right side: date & "Created by" under a line -->
  <div style="text-align: right;">
    <p style="margin: 0; font-size: 14px;">
      Generated on: <strong>$today</strong>
    </p>

    <hr style="border: 0; border-top: 1px solid #fff; margin: 6px 0;" />

    <p style="margin: 0; font-size: 14px;">
      Created by:
      <a href="https://kubedeck.io" target="_blank" style="color: #fff; text-decoration: none;">
        🌐 kubedeck.io
      </a>
    </p>
  </div>
</div>

<div class="container">
    <h1>Cluster Summary</h1>
    <p><strong>Cluster Name:</strong> $clusterName</p>
    <p><strong>Kubernetes Version:</strong> $k8sVersion</p>
    <div class="compatibility">⚠️ <strong>$compatibilityCheck</strong></div>

    <h2>📊 Cluster Metrics Summary</h2>
    <table>
        <tr>
            <td>🚀 Nodes: $totalNodes</td>
            <td>🟩 Healthy: $healthyNodes</td>
            <td>🟥 Issues: $issueNodes</td>
        </tr>
        <tr>
            <td>📦 Pods: $totalPods</td>
            <td>🟩 Running: $runningPods</td>
            <td>🟥 Failed: $failedPods</td>
        </tr>
        <tr>
            <td>🔄 Restarts: $totalRestarts</td>
            <td>🟨 Warnings: $warnings</td>
            <td>🟥 Critical: $critical</td>
        </tr>
        <tr>
            <td>⏳ Pending Pods: $pendingPods</td>
            <td>🟡 Waiting: $pendingPods</td>
            <td></td>
        </tr>
        <tr>
            <td>⚠️ Stuck Pods: $stuckPods</td>
            <td>❌ Stuck: $stuckPods</td>
            <td></td>
        </tr>
        <tr>
            <td>📉 Job Failures: $jobFailures</td>
            <td>🔴 Failed: $jobFailures</td>
            <td></td>
        </tr>
    </table>

    <h2>📊 Pod Distribution</h2>
    <table>
        <tr>
            <td>Avg: <strong>$podAvg</strong></td>
            <td>Max: <strong>$podMax</strong></td>
            <td>Min: <strong>$podMin</strong></td>
            <td>Total Nodes: <strong>$podTotalNodes</strong></td>
        </tr>
    </table>

    <h2>💾 Resource Usage</h2>
    <table>
        <tr>
            <td>🖥  CPU Usage: <strong>$cpuUsage%</strong></td>
            <td>$cpuStatus</td>
        </tr>
        <tr>
            <td>💾 Memory Usage: <strong>$memUsage%</strong></td>
            <td>$memStatus</td>
        </tr>
    </table>
</div>
</body>
</html>
"@

    # Save the updated HTML report
    $htmlTemplate | Set-Content $outputPath
    Write-Host "✅ Report generated successfully: $outputPath"
}

# Example usage:
Generate-K8sHTMLReport -outputPath "output-report.html"
