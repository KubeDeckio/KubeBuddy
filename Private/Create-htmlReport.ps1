function Generate-K8sHTMLReport {
  param (
    [string]$outputPath,
    [string]$version = "v0.0.1",
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ClusterName,
    [switch]$aks
  )

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
  Write-Host -NoNewline "`n🤖 Fetching Cluster Information..." -ForegroundColor Yellow
  $clusterSummaryRaw = Show-ClusterSummary -Html *>&1  # Captures output while displaying it
  write-Host "`r🤖 Cluster Information fetched.   " -ForegroundColor Green

  # **Run AKS Best Practices Checks**
  if ($aks) {
    Write-Host -NoNewline "`n🤖Running AKS Best Practices Checklist..." -ForegroundColor Cyan
    $aksBestPractices = Invoke-AKSBestPractices -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -Html
    # $aksBestPractices = [PSCustomObject]$aksBestPractices
    Write-Host "`r🤖 AKS Information fetched.          " -ForegroundColor Green

    # Extract key values
    $aksPass = $aksBestPractices.Passed
    $aksFail = $aksBestPractices.Failed
    $aksTotal = $aksBestPractices.Total
    $aksScore = $aksBestPractices.Score
    $aksRating = $aksBestPractices.Rating
    $aksReportData = $aksBestPractices.Data
  
    # Convert best practices table into a collapsible section
    $collapsibleAKSHtml = ConvertToCollapsible -Id "aksSummary" -defaultText "Show Best Practices Report" -content $aksReportData
  
    # **Hero Rating Section**
    $ratingColorClass = switch ($aksRating) {
      "A" { "normal" }
      "B" { "warning" }
      "C" { "warning" }
      "D" { "critical" }
      "F" { "critical" }
      default { "unknown" }
    }

    

    $heroRatingHtml = @"
<h2>AKS Best Practices Summary</h2>
<div class="hero-metrics">
  <div class="metric-card normal">✅ Passed: <strong>$aksPass</strong></div>
  <div class="metric-card critical">❌ Failed: <strong>$aksFail</strong></div>
  <div class="metric-card default">📊 Total Checks: <strong>$aksTotal</strong></div>
  <div class="metric-card $ratingColorClass">🎯 Score: <strong>$aksScore%</strong></div>
  <div class="metric-card $ratingColorClass">⭐ Rating: <strong>$aksRating</strong></div>
</div>
"@

    $aksHealthCheck = @"
  <!-- AKS summary Container -->
  <div class="container">
  <h1 id="aks">AKS Best Practices Details</h1>
  $heroRatingHtml
  <h2 id="aksFindings">AKS Best Practices Results</h2>
  <div class="table-container">
  $collapsibleAKSHtml
  </div>
  </div>
"@


    $aksMenuItem = @"
<li><a href="#aks">AKS Best Practices</a></li>
"@
  }

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

  $leftoverdebugHtml = Show-LeftoverDebugPods -Html -PageSize 999
  $collapsibleLeftoverdebugHtml = ConvertToCollapsible -Id "leftoverDebug" -defaultText "Show Table" -content $leftoverdebugHtml

  $stuckJobHtml = Show-StuckJobs -Html -PageSize 999
  $collapsibleStuckJobHtml = ConvertToCollapsible -Id "stuckJobs" -defaultText "Show Table" -content $stuckJobHtml

  $jobFailHtml = Show-FailedJobs -Html -PageSize 999
  $collapsibleJobFailHtml = ConvertToCollapsible -Id "jobFail" -defaultText "Show Table" -content $jobFailHtml

  $servicesWithoutEndpointsHtml = Show-ServicesWithoutEndpoints -Html -PageSize 999
  $collapsibleServicesWithoutEndpointsHtml = ConvertToCollapsible -Id "servicesWithoutEndpoints" -defaultText "Show Table" -content $servicesWithoutEndpointsHtml

  $publicServicesHtml = Check-PubliclyAccessibleServices -Html -PageSize 999
  $collapsiblePublicServicesHtml = ConvertToCollapsible -Id "publicServices" -defaultText "Show Table" -content $publicServicesHtml

  $unmountedpvHtml = Show-UnusedPVCs  -Html -PageSize 999
  $collapsibleUnmountedpvHtml = ConvertToCollapsible -Id "unmountedPV" -defaultText "Show Table" -content $unmountedpvHtml

  $rbacmisconfigHtml = Check-RBACMisconfigurations -Html -PageSize 999
  $collapsibleRbacmisconfigHtml = ConvertToCollapsible -Id "rbacMisconfig" -defaultText "Show Table" -content $rbacmisconfigHtml

  $rbacOverexposureHtml = Check-RBACOverexposure -Html -PageSize 999
  $collapsibleRbacOverexposureHtml = ConvertToCollapsible -Id "rbacOverexposure" -defaultText "Show Table" -content $rbacOverexposureHtml

  $orphanedConfigMapsHtml = Check-OrphanedConfigMaps -Html -PageSize 999
  $collapsibleOrphanedConfigMapsHtml = ConvertToCollapsible -Id "orphanedConfigMaps" -defaultText "Show Table" -content $orphanedConfigMapsHtml

  $orphanedSecretsHtml = Check-OrphanedSecrets -Html -PageSize 999
  $collapsibleOrphanedSecretsHtml = ConvertToCollapsible -Id "orphanedSecrets" -defaultText "Show Table" -content $orphanedSecretsHtml

  $podsRootHtml = Check-PodsRunningAsRoot -Html -PageSize 999
  $collapsiblePodsRootHtml = ConvertToCollapsible -Id "podsRoot" -defaultText "Show Table" -content $podsRootHtml

  $privilegedContainersHtml = Check-PrivilegedContainers -Html -PageSize 999
  $collapsiblePrivilegedContainersHtml = ConvertToCollapsible -Id "privilegedContainers" -defaultText "Show Table" -content $privilegedContainersHtml

  $hostPidNetHtml = Check-HostPidAndNetwork -Html -PageSize 999
  $collapsibleHostPidNetHtml = ConvertToCollapsible -Id "hostPidNet" -defaultText "Show Table" -content $hostPidNetHtml


  $eventSummaryHtml = Show-KubeEvents -Html -PageSize 999
  $collapsibleEventSummaryHtml = ConvertToCollapsible -Id "eventSummary" -defaultText "Show Table" -content $eventSummaryHtml

  # Convert output array to a single string
  $clusterSummaryText = $clusterSummaryRaw -join "`n"

  # Debugging: Print the exact raw captured output
  # Write-Host "🔍 Full Cluster Summary Output:"
  # Write-Host $clusterSummaryText

  # Function to extract numerical values correctly
  function Extract-Metric($label, $data) {
    if ($data -match "$label\s*:\s*([\d]+)") {
      return [int]$matches[1]
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


  # Extract Compatibility Check and Set Status Class
  $compatibilityCheck = "Unknown"
  $compatibilityClass = "unknown"

  if ($clusterSummaryText -match "⚠️\s+(Cluster is running an outdated version:[^\n]+)") {
    $compatibilityCheck = $matches[1].Trim()
    $compatibilityClass = "warning"
  }
  elseif ($clusterSummaryText -match "✅ Cluster is up to date \((.*?)\)") {
    $compatibilityCheck = "✅ Cluster is up to date ($matches[1])"
    $compatibilityClass = "healthy"
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

  # **Extract Warnings & Errors from Events**
  $eventWarnings = Extract-Metric "⚠️ Warnings"  $clusterSummaryText
  $eventErrors = Extract-Metric "❌ Errors"      $clusterSummaryText

  # Extract Pod Distribution
  $podAvg = if ($clusterSummaryText -match "📊 Pod Distribution: Avg: ([\d.]+)") { $matches[1] } else { "0" }
  $podMax = if ($clusterSummaryText -match "Max: ([\d.]+)") { $matches[1] } else { "0" }
  $podMin = if ($clusterSummaryText -match "Min: ([\d.]+)") { $matches[1] } else { "0" }
  $podTotalNodes = if ($clusterSummaryText -match "Total Nodes: ([\d]+)") { $matches[1] } else { "0" }

  # Extract CPU and Memory Usage
  $cpuUsage = if ($clusterSummaryText -match "🖥  CPU Usage:\s*([\d.]+)%") { 
    [double]$matches[1] 
  }
  else { 
    0 
  }
  $cpuStatus = if ($clusterSummaryText -match "🖥  CPU Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }

  $memUsage = if ($clusterSummaryText -match "💾 Memory Usage:\s*([\d.]+)%") { 
    [double]$matches[1] 
  }
  else { 
    0 
  }  $memStatus = if ($clusterSummaryText -match "💾 Memory Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }

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
  $today = (Get-Date).ToUniversalTime().ToString("MMMM dd, yyyy HH:mm:ss 'UTC'")
  $year = (Get-Date).ToUniversalTime().ToString("yyyy")

  # Get thresholds from config or use defaults
  $thresholds = Get-KubeBuddyThresholds -Silent

  # Define classes based on config-defined thresholds
  $errorClass = if ($eventErrors -ge $thresholds.event_errors_critical) { "critical" } `
    elseif ($eventErrors -ge $thresholds.event_errors_warning) { "warning" } `
    else { "normal" }


  $warningClass = if ($eventWarnings -ge $thresholds.event_warnings_critical) { "critical" } `
    elseif ($eventWarnings -ge $thresholds.event_warnings_warning) { "warning" } `
    else { "normal" }

  $cpuClass = if ($cpuUsage -ge $thresholds.cpu_critical) { "critical" } `
    elseif ($cpuUsage -ge $thresholds.cpu_warning) { "warning" } `
    else { "normal" }

  $memClass = if ($memUsage -ge [double]$thresholds.mem_critical) { "critical" } `
    elseif ($memUsage -ge [double]$thresholds.mem_warning) { "warning" } `
    else { "normal" }


  # Build the HTML Template
  $htmlTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kubernetes Cluster Report</title>
    <!-- Add favicon here -->
    <link rel="icon" href="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/assets/images/favicon.ico" type="image/x-icon">
<style>
    @import url('https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;700&display=swap');

    html {
      scroll-behavior: smooth; /* optional smooth scrolling */
    }
    body { 
        font-family: 'Roboto', sans-serif;
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
        max-width: 1350px; 
        margin: 20px auto; 
        background: white; 
        padding: 20px; 
        border-radius: 8px; 
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2); 
    }
    .compatibility {
        padding: 12px;
        border-radius: 5px;
        font-weight: bold;
        text-align: center;
        color: #ffffff;
        box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.2);
    }
    
    /* Colors based on cluster status */
    .warning { background: #ffeb3b; } /* Yellow */
    .healthy { background: #4CAF50; } /* Green */
    .unknown { background: #9E9E9E; } /* Gray */
    .table-container {
    overflow-x: auto; /* Enables horizontal scrolling */
    width: 100%;
    max-width: 100%;
    }
    table { 
        width: 100%; 
        border-collapse: collapse; 
        margin: 20px 0; 
        font-size: 14px; 
        text-align: left; 
    }
    table, th, td { 
        white-space: nowrap; /* Prevents text from wrapping */
        border: 1px solid #cfd8dc; 
        padding: 12px; 
        text-align: left;
    }
    th { 
        background-color: #0071FF; 
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

    #printContainer {
        text-align: right;
        margin-bottom: 15px;
    }
    #printContainer button {
        background-color: #0071FF;
        color: white;
        padding: 10px 15px;
        border: none;
        cursor: pointer;
        font-size: 16px;
        border-radius: 5px;
    }
    #printContainer button:hover {
        background-color: #005ad1;
    }
    #savePdfBtn {
        background-color: #0071FF;
        color: white;
        padding: 8px 12px;
        font-size: 14px;
        font-weight: bold;
        border: none;
        cursor: pointer;
        border-radius: 5px;
        margin-top: 10px;
    }
    #savePdfBtn:hover {
        background-color: #005ad1;
    }
    @media print {
        #savePdfBtn { display: none; } /* Hide button in PDF */
        table {
            width: 100%;
            table-layout: fixed;
            border-collapse: collapse;
        }
    
        th, td {
            white-space: normal !important;
            overflow: visible !important;
            word-wrap: break-word;
            padding: 8px;
            border: 1px solid #ddd;
        }
    
        .table-container {
            overflow: visible !important;
            height: auto !important;
        }
    }
    
    /* Hide button when printing */
    @media print {
        #printContainer { display: none; }
        details { display: block; } /* Expand all details on print */
    }


    /* Floating TOC (Initially Collapsed) */
    #toc {
        position: fixed;
        top: 50%;
        left: 0;
        transform: translateY(-50%);
        background-color: #0071FF; /* Fully blue when collapsed */
        border: none;
        border-radius: 0 8px 8px 0;
        box-shadow: 2px 2px 8px rgba(0,0,0,0.15);
        width: 40px; /* Small when collapsed */
        height: 100px; /* Ensures the blue part covers the visible section */
        transition: all 0.3s ease-in-out;
        overflow: hidden;
        z-index: 9999;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    
    /* Menu Button (Always Visible in Collapsed State) */
    #toc-toggle {
        color: white;
        padding: 15px 5px;
        writing-mode: vertical-rl;
        text-align: center;
        font-weight: bold;
        cursor: pointer;
        user-select: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 100%; /* Takes full width when collapsed */
    }

    /* Expanded TOC */
    #toc.open {
        background-color: white;
        width: 200px; /* Expanded width */
        height: auto;
        padding: 10px;
    }
    
    /* Hide the blue when expanded */
    #toc.open #toc-toggle {
        display: none;
    }
    
    /* TOC Content (Initially Hidden) */
    #toc-content {
        display: none;
        padding: 10px;
    }
    
    /* Show TOC Content When Open */
    #toc.open #toc-content {
        display: block;
    }
    
    /* Close Button */
    #toc-close {
        position: absolute;
        top: 5px;
        right: 5px;
        background: none;
        border: none;
        color: #37474f;
        font-size: 16px;
        font-weight: bold;
        cursor: pointer;
    }
    
    /* TOC Links Styling */
    #toc ul {
        list-style: none;
        margin: 0;
        padding: 0;
    }
    
    #toc ul li {
        margin: 8px 0;
    }
    
    #toc ul li a {
        display: block;
        color: #37474f;
        text-decoration: none;
        font-size: 14px;
        padding: 5px 0;
        transition: color 0.2s ease-in-out;
    }
    
    #toc ul li a:hover {
        color: #0071FF;
    }
    
    /* Nested Lists (Indentation) */
    #toc ul li details ul {
        padding-left: 15px;
    }
    
    /* Auto-close menu on small screens */
    @media(max-width: 800px) {
        #toc {
            display: none;
        }
    }

    details ul {
      margin-left: 1.5em;
    }
    .hero-metrics {
        display: flex;
        justify-content: space-around;
        margin-bottom: 20px;
        flex-wrap: wrap;
    }
    .metric-card {
        text-align: center;
        padding: 20px;
        border-radius: 8px;
        color: white;
        font-size: 20px;
        font-weight: bold;
        min-width: 150px;
        flex: 1;
        margin: 10px;
        box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.2);
    }
    
    /* Dynamic Colors */
    .normal { background-color: #388e3c; } /* Green (Healthy) */
    .warning { background-color: #ffa000; } /* Orange (Warning) */
    .critical { background-color: #B71C1C; } /* Red (Critical) */
    .default { background-color: #0071FF; }
    
    /* Responsive Adjustments */
    @media (max-width: 600px) {
        .hero-metrics {
            flex-direction: column;
            align-items: center;
        }
        .metric-card {
            width: 80%;
        }
    }

    .footer {
    background-color: #263238;
    color: white;
    text-align: center;
    padding: 15px 20px;
    font-size: 14px;
    position: relative; /* This allows the footer to stay below content */
    }
    .footer a {
        color: #80cbc4;
        text-decoration: none;
    }
    .footer a:hover {
        text-decoration: underline;
    }
</style>
</head>
<body>
<div id="toc">
    <div id="toc-toggle">MENU</div> <!-- Collapsed button -->
    <div id="toc-content">
        <button id="toc-close">✖</button> <!-- Close Button -->
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
        <li><a href="#daemonsets">DaemonSets</a></li>
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
        <li><a href="#crashloop">Pods in Crashloop</a></li>
        <li><a href="#debugpods">Running Debug Pods</a></li>
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
    <li><a href="#publicServices">Public Services</a></li>
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
            <li><a href="#rbacOverexposure">RBAC Overexposure</a></li>
            <li><a href="#orphanedconfigmaps">Orphaned ConfigMaps</a></li>
            <li><a href="#orphanedsecrets">Orphaned Secrets</a></li>
            <li><a href="#podsRoot">Pods Running as Root</a></li>
            <li><a href="#privilegedContainers">Privileged Containers</a></li>
            <li><a href="#hostPidNet">hostPID / hostNetwork</a></li>
        </ul>
        </details>
    <li><a href="#clusterwarnings">Kubernetes Events</a></li>
    $aksMenuItem
</ul>
</div>
</div>
<div id="top"></div>
<div class="header">
  <div style="display: flex; flex-direction: column;">
    <span>Kubernetes Cluster Report: $clusterName</span>
    <span style="font-size: 12px;">
      Powered by 
      <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" 
           alt="KubeBuddy Logo" 
           style="height: 70px; vertical-align: middle;">
    </span>
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

    <!-- Save as PDF Button -->
    <div id="printContainer">
      <button id="savePdfBtn">📄 Save as PDF</button>
    </div>
  </div>
  </div>
</div>


<div class="container">
    <h1 id="summary">Cluster Summary</h1>
    <p><strong>Cluster Name:</strong> $clusterName</p>
    <p><strong>Kubernetes Version:</strong> $k8sVersion</p>
    <div class="compatibility $compatibilityClass"><strong>$compatibilityCheck</strong></div>

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
    <div class="hero-metrics">
        <div class="metric-card $cpuClass">🖥 CPU: <strong>$cpuUsage%</strong> <br><span>$cpuStatus</span></div>
        <div class="metric-card $memClass">💾 Memory: <strong>$memUsage%</strong> <br><span>$memStatus</span></div>
    </div>
        <!-- Hero Metrics Section -->
    <h2>Cluster Events</h2>
    <div class="hero-metrics">
        <div class="metric-card $errorClass">❌ Errors: <strong>$eventErrors</strong></div>
        <div class="metric-card $warningClass">⚠️ Warnings: <strong>$eventWarnings</strong></div>
    </div>
    </div>
</div>
<!-- Node Conditions Container -->
<div class="container">
<h1>Node Conditions & Resources</h1>
  <h2 id="nodecon">Node Conditions</h2>
  <div class="table-container">
  $collapsibleNodeSection
  </div>
  <h2 id="noderesource">Node Resources</h2>
  <div class="table-container">
  $collapsibleNodeResources
  </div>
</div>
<!-- Namespace Container -->
<div class="container">
<h1 id="namespaces">Namespaces</h1>
  <h2>Empty Namespaces</h2>
  <div class="table-container">
  $collapsibleEmptyNsHtmls
  </div>
</div>
<!-- Workload Container -->
<div class="container">
<h1 id="workloads">Workloads</h1>
  <h2 id=daemonsets>DaemonSets Not Fully Running</h2>
  <div class="table-container">
  $collapsibleDsIssuesHtml
  </div>
</div>
<!-- Pods Container -->
<div class="container">
<h1 id="pods">Pods</h1>
  <h2 id="podrestarts">Pods with High Restarts</h2>
  <div class="table-container">
  $collapsiblePodsRestartHtml
  </div>
  <h2 id="podlong">Long Running Pods</h2>
  <div class="table-container">
  $collapsiblePodLongRunningHtml
  </div>
  <h2 id="podfail">Failed Pods</h2>
  <div class="table-container">
  $collapsiblePodFailHtml
  </div>
  <h2 id="podpending">Pending Pods</h2>
  <div class="table-container">
  $collapsiblePodPendingHtml
  </div>
  <h2 id="crashloop">CrashLoopBackOff Pods</h2>
  <div class="table-container">
  $collapsibleCrashloopHtml
  </div>
    <h2 id="debugpods">Running Debug Pods</h2>
  <div class="table-container">
  $collapsibleLeftoverdebugHtml
  </div>
</div>
<!-- Job Container -->
<div class="container">
<h1 id="jobs">Jobs</h1>
  <h2 id="stuckjobs">Stuck Jobs</h2>
  <div class="table-container">
  $collapsibleStuckJobHtml
  </div>
  <h2 id="failedjobs">Job Failures</h2>
  <div class="table-container">
  $collapsibleJobFailHtml
  </div>
  </div>

<!-- Networking Container -->
<div class="container">
<h1 id="networking">Networking</h1>
  <h2 id="servicenoendpoints">Services without Endpoints</h2>
  <div class="table-container">
  $collapsibleServicesWithoutEndpointsHtml
  </div>
  <h2 id="publicServices">Publicly Accessible Services</h2>
  <div class="table-container">
  $collapsiblePublicServicesHtml
  </div>
</div>

<!-- Storage Container -->
<div class="container">
<h1 id="storage">Storage</h1>
  <h2 id="unmountedpv">Unmounted Persistent Volumes</h2>
  <div class="table-container">
  $collapsibleUnmountedpvHtml
  </div>
  </div>

<!-- Security Container -->
<div class="container">
<h1 id="security">Security</h1>
  <h2 id="rbacmisconfig">RBAC Misconfigurations</h2>
  <div class="table-container">
  $collapsibleRbacmisconfigHtml
  </div>
  <h2 id="rbacOverexposure">RBAC Overexposure</h2>
  <div class="table-container">
  $collapsibleRbacOverexposureHtml
  </div>
  <h2 id="orphanedconfigmaps">Orphaned ConfigMaps</h2>
  <div class="table-container">
  $collapsibleOrphanedConfigMapsHtml
  </div>
  <h2 id="orphanedsecrets">Orphaned Secrets</h2>
  <div class="table-container">
  $collapsibleOrphanedSecretsHtml
  </div>
  <h2 id="podsRoot">Pods Running as Root</h2>
  <div class="table-container">
  $collapsiblePodsRootHtml
  </div>
  <h2 id="privilegedContainers">Privileged Containers</h2>
  <div class="table-container">
  $collapsiblePrivilegedContainersHtml
  </div>
  <h2 id="hostPidNet">hostPID / hostNetwork Enabled</h2>
  <div class="table-container">
  $collapsibleHostPidNetHtml
  </div>
</div>

  <!-- Kube Event Container -->
  <div class="container">
  <h1 id="kubeevents">Kubernetes Warning Events</h1>
  <h2 id="clusterwarnings">Recent Cluster Warnings</h2>
  <div class="table-container">
  $collapsibleEventSummaryHtml
  </div>
  </div>
  $aksHealthCheck
    <footer class="footer">
        <p><strong>Report generated by Kubebuddy $version</strong> on $today</p>
        <p>&copy; $year Kubebuddy | <a href="https://kubedeck.io" target="_blank">KubeDeck.io</a></p>
        <p><em>This report is a snapshot of the cluster state at the time of generation. It may not reflect real-time changes. Always verify configurations before making critical decisions.</em></p>
    </footer>
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
    document.addEventListener("DOMContentLoaded", function() {
        const toc = document.getElementById("toc");
        const tocToggle = document.getElementById("toc-toggle");
        const tocContent = document.getElementById("toc-content");
        const tocClose = document.getElementById("toc-close");
    
        // Start in collapsed state
        toc.classList.remove("open");
        tocContent.style.display = "none";
    
        tocToggle.addEventListener("click", function() {
            toc.classList.add("open");
            tocContent.style.display = "block"; // Show content
            toc.style.width = "200px"; // Expand
            toc.style.height = "auto";
        });
    
        tocClose.addEventListener("click", function() {
            toc.classList.remove("open");
            tocContent.style.display = "none"; // Hide content
            toc.style.width = "40px"; // Shrink
            toc.style.height = "100px"; // Keep blue part covering it
        });
    
        // Auto-close TOC on scroll
        let lastScrollY = window.scrollY;
        window.addEventListener("scroll", function() {
            if (Math.abs(window.scrollY - lastScrollY) > 50) { // If scrolled more than 50px
                toc.classList.remove("open");
                tocContent.style.display = "none";
                toc.style.width = "40px";
                toc.style.height = "100px";
            }
            lastScrollY = window.scrollY;
        });
    });
    document.getElementById("savePdfBtn").addEventListener("click", function() {
        // Store original open state of all collapsible sections
        const detailsElements = document.querySelectorAll("details");
        const detailsStates = new Map();
        
        detailsElements.forEach(detail => {
            detailsStates.set(detail, detail.open);
            detail.open = true; // Expand all sections
        });
    
        // Save original table styles
        const tableContainers = document.querySelectorAll(".table-container");
        const tables = document.querySelectorAll("table");
    
        const originalStyles = [];
    
        tableContainers.forEach((container, index) => {
            originalStyles[index] = {
                overflow: container.style.overflow,
                height: container.style.height
            };
    
            // Remove scrollbars and expand tables
            container.style.overflow = "visible";
            container.style.height = "auto";
        });
    
        // Force table rows to expand fully
        tables.forEach(table => {
            table.style.width = "100%";
            table.style.tableLayout = "fixed";
        });
    
        // Delay print to allow rendering
        setTimeout(() => {
            window.print();
        }, 500);
    
        // Restore original styles after printing
        window.onafterprint = function() {
            detailsElements.forEach(detail => {
                detail.open = detailsStates.get(detail); // Restore original state
            });
    
            tableContainers.forEach((container, index) => {
                container.style.overflow = originalStyles[index].overflow;
                container.style.height = originalStyles[index].height;
            });
    
            // Reset table styles
            tables.forEach(table => {
                table.style.tableLayout = "";
            });
        };
    });

  </script>
</body>
</html>
"@

  # Save the updated HTML report
  $htmlTemplate | Set-Content $outputPath
}

# Example usage:
# Generate-K8sHTMLReport -outputPath "output-report.html"
