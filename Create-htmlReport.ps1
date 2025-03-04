function Generate-K8sHTMLReport {
    param (
        [string]$outputPath
    )

    # Load kubebuddy.ps1
    $kubebuddyScript = "$pwd/kubebuddy.ps1"
    if (Test-Path $kubebuddyScript) {
        . $kubebuddyScript
        Write-Host "✅ Loaded kubebuddy.ps1 successfully."
    }
    else {
        Write-Host "⚠️ Warning: kubebuddy.ps1 not found. Ensure it's in the correct directory." -ForegroundColor Yellow
        return
    }

    function ConvertToCollapsible {
        param(
            [string]$Id, # unique HTML ID
            [string]$defaultText, # default <summary> label (e.g., "Show Table")
            [string]$content     # the HTML to show/hide
        )
    
        @"
<details id='$Id' style='margin:10px 0;'>
  <summary style='font-size:16px; cursor:pointer;'>$defaultText</summary>
  $content
</details>

<script>
document.addEventListener('DOMContentLoaded', function() {
  const detElem = document.getElementById('$Id');
  if (!detElem) return;

  const sum = detElem.querySelector('summary');
  detElem.addEventListener('toggle', () => {
    // If open, change label to "Hide Table", else revert to $defaultText
    sum.textContent = detElem.open ? 'Hide Table' : '$defaultText';
  });
});
</script>
"@
    }
    

    # Ensure output file is cleared before writing
    if (Test-Path $outputPath) {
        Remove-Item $outputPath -Force
    }

    # Capture console output while still displaying it
    Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Retrieving Cluster Information...             ⏳ Fetching..." -ForegroundColor Yellow
    $clusterSummaryRaw = Show-ClusterSummary -Html *>&1  # Captures output while displaying it
    write-Host "`r🤖 Retrieving Cluster Information...             ✅ Done!      " -ForegroundColor Green

    # Capture all nodes at once so we get a complete ASCII table:
    $nodeConditionsHtml = Show-NodeConditions -Html -PageSize 999
    $collapsibleNodeSection = ConvertToCollapsible -Id "nodeConditions" -defaultText "Show Table" -content $nodeConditionsHtml

    $nodeResources = Show-NodeResourceUsage -PageSize 999 -Html
    $collapsibleNodeResources = ConvertToCollapsible -Id "nodeResources" -defaultText "Show Table" -content $nodeResources

    $emptyNsHtml = Show-EmptyNamespaces -PageSize 999 -Html
    $collapsibleEmptyNsHtmls = ConvertToCollapsible -Id "emptyNamespace" -defaultText "Show Table" -content $emptyNsHtml

    $dsIssuesHtml = Show-DaemonSetIssues -PageSize 999 -Html
    $collapsibleDsIssuesHtml = ConvertToCollapsible -Id "daemonSetIssues" -defaultText "Show Table" -content $dsIssuesHtml

    $podsRestartHtml = Show-PodsWithHighRestarts -Html -PageSize 999
    $collapsiblePodsRestartHtml = ConvertToCollapsible -Id "podsRestart" -defaultText "Show Table" -content $podsRestartHtml

    $podLongRunningHtml = Show-LongRunningPods -Html -PageSize 999
    $collapsiblePodLongRunningHtml = ConvertToCollapsible -Id "podLongRunning" -defaultText "Show Table" -content $podLongRunningHtml

    $podFailHtml = Show-FailedPods -Html -PageSize 999
    $collapsiblePodFailHtml = ConvertToCollapsible -Id "podFail" -defaultText "Show Table" -content $podFailHtml

    $podpendHtml = Show-PendingPods -Html -PageSize 999
    $collapsiblePodPendingHtml = ConvertToCollapsible -Id "podPending" -defaultText "Show Table" -content $podpendHtml

    $crashloopHtml = Show-CrashLoopBackOffPods -Html -PageSize 999
    $collapsibleCrashloopHtml = ConvertToCollapsible -Id "crashloop" -defaultText "Show Table" -content $crashloopHtml

    $stuckJobHtml = Show-StuckJobs -Html -PageSize 999
    $collapsibleStuckJobHtml = ConvertToCollapsible -Id "stuckJobs" -defaultText "Show Table" -content $stuckJobHtml

    $jobFailHtml = Show-FailedJobs -Html -PageSize 999
    $collapsibleJobFailHtml = ConvertToCollapsible -Id "jobFail" -defaultText "Show Table" -content $jobFailHtml

    $servicesWithoutEndpointsHtml = Show-ServicesWithoutEndpoints -Html -PageSize 999
    $collapsibleServicesWithoutEndpointsHtml = ConvertToCollapsible -Id "servicesWithoutEndpoints" -defaultText "Show Table" -content $servicesWithoutEndpointsHtml

    $unmountedpvHtml = Show-UnusedPVCs  -Html -PageSize 999
    $collapsibleUnmountedpvHtml = ConvertToCollapsible -Id "unmountedPV" -defaultText "Show Table" -content $unmountedpvHtml

    $rbacmisconfigHtml = Check-RBACMisconfigurations -Html -PageSize 999
    $collapsibleRbacmisconfigHtml = ConvertToCollapsible -Id "rbacMisconfig" -defaultText "Show Table" -content $rbacmisconfigHtml

    $orphanedConfigMapsHtml = Check-OrphanedConfigMaps -Html -PageSize 999
    $collapsibleOrphanedConfigMapsHtml = ConvertToCollapsible -Id "orphanedConfigMaps" -defaultText "Show Table" -content $orphanedConfigMapsHtml

    $orphanedSecretsHtml = Check-OrphanedSecrets -Html -PageSize 999
    $collapsibleOrphanedSecretsHtml = ConvertToCollapsible -Id "orphanedSecrets" -defaultText "Show Table" -content $orphanedSecretsHtml

    # Convert output array to a single string
    $clusterSummaryText = $clusterSummaryRaw -join "`n"

    # Debugging: Print the exact raw captured output
    # Write-Host "🔍 Full Cluster Summary Output:"
    # Write-Host $clusterSummaryText

    # Function to extract numerical values correctly
    function Extract-Metric($label, $data) {
        if ($data -match "$label\s*:\s*([\d]+)") {
            return $matches[1]
        }
        return "0"
    }

    # Extract Cluster Name and Kubernetes Version properly
    $clusterName = "Unknown"
    $k8sVersion = "Unknown"

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
    $totalNodes = Extract-Metric "🚀 Nodes"         $clusterSummaryText
    $healthyNodes = Extract-Metric "🟩 Healthy"       $clusterSummaryText
    $issueNodes = Extract-Metric "🟥 Issues"        $clusterSummaryText
    $totalPods = Extract-Metric "📦 Pods"          $clusterSummaryText
    $runningPods = Extract-Metric "🟩 Running"       $clusterSummaryText
    $failedPods = Extract-Metric "🟥 Failed"        $clusterSummaryText
    $totalRestarts = Extract-Metric "🔄 Restarts"      $clusterSummaryText
    $warnings = Extract-Metric "🟨 Warnings"      $clusterSummaryText
    $critical = Extract-Metric "🟥 Critical"      $clusterSummaryText
    $pendingPods = Extract-Metric "⏳ Pending Pods"   $clusterSummaryText
    $stuckPods = Extract-Metric "⚠️ Stuck Pods"    $clusterSummaryText
    $jobFailures = Extract-Metric "📉 Job Failures"  $clusterSummaryText

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

    # # Debugging: Print extracted values
    # Write-Host "📊 Extracted Values:"
    # Write-Host "Cluster Name: $clusterName"
    # Write-Host "Kubernetes Version: $k8sVersion"
    # Write-Host "Compatibility: $compatibilityCheck"
    # Write-Host "Nodes: $totalNodes, Healthy: $healthyNodes, Issues: $issueNodes"
    # Write-Host "Pods: $totalPods, Running: $runningPods, Failed: $failedPods"
    # Write-Host "Restarts: $totalRestarts, Warnings: $warnings, Critical: $critical"
    # Write-Host "Pending Pods: $pendingPods, Stuck Pods: $stuckPods, Job Failures: $jobFailures"
    # Write-Host "Pod Distribution -> Avg: $podAvg, Max: $podMax, Min: $podMin, Total Nodes: $podTotalNodes"
    # Write-Host "CPU Usage: $cpuUsage%, Status: $cpuStatus"
    # Write-Host "Memory Usage: $memUsage%, Status: $memStatus"

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
    html {
      scroll-behavior: smooth; /* optional smooth scrolling */
    }
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
        /* “Back to Top” button style */
    #backToTop {
      position: fixed;
      bottom: 20px;
      right: 20px;
      background-color: #0071FF;
      color: #fff;
      padding: 10px 15px;
      border-radius: 5px;
      text-decoration: none;
      font-size: 14px;
      font-weight: bold;
      box-shadow: 0 2px 6px rgba(0,0,0,0.3);
      display: none; /* hide by default */
      transition: opacity 0.3s ease;
    }
    #backToTop:hover {
      background-color: #005ad1;
    }
          /* Floating TOC Menu */
    #toc {
      position: fixed;
      top: 50%;                /* centers vertically in the viewport */
      left: 0;                 /* pinned to the left side */
      transform: translateY(-50%); /* offset by 50% to center exactly */
      background-color: #fff;
      border: 1px solid #cfd8dc;
      border-right: none;          /* remove right border (since pinned left) */
      border-radius: 0 8px 8px 0;  /* rounding on right side only */
      box-shadow: 2px 2px 8px rgba(0,0,0,0.15); /* slight shadow to the right */
      padding: 10px 15px;
      width: 180px;
      z-index: 9999;           /* floats on top of other elements */
    }
    #toc h3 {
      margin-top: 0;
      font-size: 16px;
      text-align: center;
    }
    #toc ul {
      list-style: none;
      margin: 0;
      padding: 0;
    }
    #toc ul li a {
      display: block;
      color: #37474f;
      text-decoration: none;
      margin: 5px 0;
      font-size: 14px;
      transition: color 0.2s ease;
    }
    #toc ul li a:hover {
      color: #0071FF;
    }
    /* Adjust for narrower screens */
    @media(max-width: 800px) {
      #toc {
        display: none; /* hide the floating menu on smaller devices, or make it absolute or a hamburger menu */
      }
    }
    details ul {
      margin-left: 1.5em;
    }
</style>
</head>
<body>
<nav id="toc">
  <h3>Sections</h3>
<ul>
  <li><a href="#summary">Cluster Summary</a></li>

  <!-- Collapsible "Nodes" section -->
  <li>
    <details>
      <summary>Nodes</summary>
      <ul>
        <li><a href="#nodecon">Node Conditions</a></li>
        <li><a href="#noderesource">Node Resources</a></li>
      </ul>
    </details>
  </li>

  <li><a href="#namespaces">Namespaces</a></li>

  <!-- Collapsible "Workloads" section -->
    <li>
    <details>
      <summary>Workloads</summary>
      <ul>
        <li><a href="#workloads">Workloads</a></li>
              </ul>
    </details>
  </li>

  <!-- Collapsible "Pods" section -->
  <li>
    <details>
      <summary>Pods</summary>
      <ul>
        <li><a href="#podrestarts">Pods with High Restarts</a></li>
        <li><a href="#podlong">Long Running Pods</a></li>
        <li><a href="#podfail">Failed Pods</a></li>
        <li><a href="#podpend">Pending Pods</a></li>
        <li><a href="#crashloop">Pods in crashloop</a></li>
      </ul>
    </details>
  </li>

  <!-- Collapsible "Jobs" section -->
    <li>
    <details>
      <summary>Jobs</summary>
      <ul>
        <li><a href="#stuckjobs">Stuck Jobs</a></li>
        <li><a href="#failedjobs">Job Failures</a></li>
              </ul>
    </details>
  </li>

  <!-- Collapsible "Networking" section -->
    <li>
    <details>
      <summary>Networking</summary>
      <ul>
        <li><a href="#servicenoendpoints">Services without Endpoints</a></li>
              </ul>
    </details>
  </li>

    <!-- Collapsible "Storage" section -->
        <li>
        <details>
        <summary>Storage</summary>
        <ul>
            <li><a href="#unmountedpv">Unmounted Persistent Volumes</a></li>
                </ul>
        </details>

    <!-- Collapsible "Security" section -->
        <li>
        <details>
        <summary>Security</summary>
        <ul>
            <li><a href="#rbacmisconfig">RBAC Misconfigurations</a></li>
            <li><a href="#orphanedconfigmaps">Orphaned ConfigMaps</a></li>
            <li><a href="#orphanedsecrets">Orphaned Secrets</a></li>
                </ul>
        </details>
</ul>

</nav>
<div id="top"></div>
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
    <h1 id="summary">Cluster Summary</h1>
    <p><strong>Cluster Name:</strong> $clusterName</p>
    <p><strong>Kubernetes Version:</strong> $k8sVersion</p>
    <div class="compatibility">⚠️ <strong>$compatibilityCheck</strong></div>

    <h2>Cluster Metrics Summary</h2>
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

    <h2>Pod Distribution</h2>
    <table>
        <tr>
            <td>Avg: <strong>$podAvg</strong></td>
            <td>Max: <strong>$podMax</strong></td>
            <td>Min: <strong>$podMin</strong></td>
            <td>Total Nodes: <strong>$podTotalNodes</strong></td>
        </tr>
    </table>

    <h2>Resource Usage</h2>
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
<!-- Node Conditions Container -->
<div class="container">
<h1>Node Conditions & Resources</h1>
  <h2 id="nodecon">Node Conditions</h2>
  $collapsibleNodeSection
  <h2 id="noderesource">Node Resources</h2>
  $collapsibleNodeResources
</div>
<!-- Namespace Container -->
<div class="container">
<h1 id="namespaces">Namespaces</h1>
  <h2>Empty Namespaces</h2>
  $collapsibleEmptyNsHtmls
</div>
<!-- Workload Container -->
<div class="container">
<h1 id="workloads">Workloads</h1>
  <h2>DaemonSets Not Fully Running</h2>
  $collapsibleDsIssuesHtml
</div>
<!-- Pods Container -->
<div class="container">
<h1 id="pods">Pods</h1>
  <h2 id="podrestarts">Pods with High Restarts</h2>
  $collapsiblePodsRestartHtml
  <h2 id="podlong">Long Running Pods</h2>
  $collapsiblePodLongRunningHtml
  <h2 id="podfail">Failed Pods</h2>
  $collapsiblePodFailHtml
  <h2 id="podpending">Pending Pods</h2>
  $collapsiblePodPendingHtml
  <h2 id="crashloop">CrashLoopBackOff Pods</h2>
  $collapsibleCrashloopHtml
</div>
<!-- Job Container -->
<div class="container">
<h1 id="jobs">Jobs</h1>
  <h2 id="stuckjobs">Stuck Jobs</h2>
  $collapsibleStuckJobHtml
  <h2 id="failedjobs">Job Failures</h2>
  $collapsibleJobFailHtml
  </div>
<!-- Networking Container -->
<div class="container">
<h1 id="jobs">Networking</h1>
  <h2 id="servicenoendpoints">Services without Endpoints</h2>
  $collapsibleServicesWithoutEndpointsHtml
</div>
<!-- Storage Container -->
<div class="container">
<h1 id="storage">Storage</h1>
  <h2 id="unmountedpv">Unmounted Persistent Volumes</h2>
  $collapsibleUnmountedpvHtml
  </div>
<!-- Security Container -->
<div class="container">
<h1 id="security">Security</h1>
  <h2 id="rbacmisconfig">RBAC Misconfigurations</h2>
  $collapsibleRbacmisconfigHtml
  <h2 id="orphanedconfigmaps">Orphaned ConfigMaps</h2>
  $collapsibleOrphanedConfigMapsHtml
  <h2 id="orphanedsecrets">Orphaned Secrets</h2>
  $collapsibleOrphanedSecretsHtml
  </div>
<!-- Back to Top Button -->
<a href="#top" id="backToTop">Back to Top</a>
<script>
    // Show/hide "Back to Top" button based on scroll
    window.addEventListener('scroll', function() {
      const button = document.getElementById('backToTop');
      // If scrolled down more than 200px, show the button, else hide it
      if (window.scrollY > 200) {
        button.style.display = 'block';
      } else {
        button.style.display = 'none';
      }
    });
  </script>
</body>
</html>
"@

    # Save the updated HTML report
    $htmlTemplate | Set-Content $outputPath
    Write-Host "`n🤖 ✅ Report generated successfully: $outputPath" -ForegroundColor Green
}

# Example usage:
Generate-K8sHTMLReport -outputPath "output-report.html"
