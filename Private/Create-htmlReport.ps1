function Generate-K8sHTMLReport {
  param (
    [string]$outputPath,
    [string]$version = "v0.0.1",
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ClusterName,
    [switch]$aks,
    [switch]$ExcludeNamespaces,
    [object]$KubeData
  )

  function ConvertToCollapsible {
    param(
      [string]$Id,
      [string]$defaultText,
      [string]$content
    )
          
    @"
<div class="collapsible-container" id='$Id'>
<details style='margin:10px 0;'>
  <summary style='font-size:16px; cursor:pointer; color:#0071FF; font-weight:bold;'>$defaultText</summary>
  <div style='padding-top: 15px;'>
    $content
  </div>
</details>
</div>
"@
  }

  # Mapping of custom check sections to navigation categories
  $sectionToNavMap = @{
    "Nodes"             = "Nodes"
    "Namespaces"        = "Namespaces"
    "Workloads"         = "Workloads"
    "Pods"              = "Pods"
    "Jobs"              = "Jobs"
    "Networking"        = "Networking"
    "Storage"           = "Storage"
    "Configuration"     = "Configuration Hygiene"
    "Security"          = "Security"
    "Kubernetes Events" = "Kubernetes Events"
  }

  if (Test-Path $outputPath) {
    Remove-Item $outputPath -Force
  }

  # Path to report-scripts.js and report-styles.css in the module directory
  $jsPath = Join-Path $PSScriptRoot "html/report-scripts.js"
  $cssPath = Join-Path $PSScriptRoot "html/report-styles.css"

  # Read the JavaScript content
  if (Test-Path $jsPath) {
    $jsContent = Get-Content -Path $jsPath -Raw
  }
  else {
    $jsContent = "// Error: report-scripts.js not found at $jsPath"
    Write-Warning "report-scripts.js not found at $jsPath. HTML features may not work."
  }

  # Read CSS content
  $cssPath = Join-Path $PSScriptRoot "html/report-styles.css"
  if (-not (Test-Path $cssPath)) {
    Write-Warning "CSS file not found at $cssPath. Using fallback styles."
    $cssContent = @"
body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f5f5f5; }
.header { background: #0071FF; color: white; padding: 10px; }
.tabs li { display: inline-block; padding: 10px 20px; cursor: pointer; }
.tabs li.active { background: #005BB5; }
.table-container { margin: 20px 0; }
table { width: 100%; border-collapse: collapse; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
.tooltip { position: relative; display: inline-block; }
.tooltip .tooltip-text { visibility: hidden; background: #333; color: white; padding: 5px; position: absolute; z-index: 1; }
.tooltip:hover .tooltip-text { visibility: visible; }
"@
  }
  else {
    $cssContent = Get-Content -Path $cssPath -Raw
  }



  Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan
  Write-Host -NoNewline "`n🤖 Fetching Cluster Information..." -ForegroundColor Yellow
  $clusterSummaryRaw = Show-ClusterSummary -Html -KubeData:$KubeData *>&1
  $apiHealthHtml = Show-ApiServerHealth -html
  Write-Host "`r🤖 Cluster Information fetched.   " -ForegroundColor Green

  
  if ($aks) {
    Write-Host -NoNewline "`n🤖 Running AKS Best Practices Checklist..." -ForegroundColor Cyan
    $aksBestPractices = Invoke-AKSBestPractices -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -Html -KubeData:$KubeData
    Write-Host "`r🤖 AKS Check Results fetched.          " -ForegroundColor Green

    $aksPass = $aksBestPractices.Passed
    $aksFail = $aksBestPractices.Failed
    $aksTotal = $aksBestPractices.Total
    $aksScore = $aksBestPractices.Score
    $aksRating = $aksBestPractices.Rating
    $aksReportData = $aksBestPractices.Data

    $collapsibleAKSHtml = ConvertToCollapsible -Id "aksSummary" -defaultText "Show Findings" -content $aksReportData


    $ratingColorClass = switch ($aksRating) {
      "A" { "normal" }
      "B" { "warning" }
      "C" { "warning" }
      "D" { "critical" }
      "F" { "critical" }
      default { "unknown" }
    }

    # Use ScoreColor directly for the score box (hex color for inline style)
    $heroRatingHtml = @"
<h2>AKS Best Practices Summary</h2>
<div class="hero-metrics">
<div class="metric-card normal">✅ Passed: <strong>$aksPass</strong></div>
<div class="metric-card critical">❌ Failed: <strong>$aksFail</strong></div>
<div class="metric-card default">📊 Total Checks: <strong>$aksTotal</strong></div>
<div class="metric-card default">🎯 Score: <strong>$aksScore%</strong></div>
<div class="metric-card $ratingColorClass">⭐ Rating: <strong>$aksRating</strong></div>
</div>
"@

    $aksHealthCheck = @"
<div class="container">
<h1 id="aks">AKS Best Practices</h1>
$heroRatingHtml
<h2 id="aksFindings">AKS Best Practices Results</h2>
<div class="table-container">
  $collapsibleAKSHtml
</div>
</div>
"@

    $aksMenuItem = @"
<li class="nav-item"><a href="#aks"><span class="material-icons">verified</span> AKS Best Practices</a></li>
"@
  }

  $checks = @(
    @{ Id = "allChecks"; Cmd = { Invoke-yamlChecks -Html -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } }
  )

  $customNavItems = @{}
  $checkStatusList = @()
  $hasCustomChecks = $false

  foreach ($check in $checks) {
    $html = & $check.Cmd
    if (-not $html) { $html = "<p>No data available for $($check.Id).</p>" }

    if ($check.Id -eq 'allChecks' -and $html -is [hashtable]) {
      $allChecksBySection = $html.HtmlBySection
      $checkStatusList += $html.StatusList
      $checkScoreList += $html.ScoreList

      $knownSections = $sectionToNavMap.Keys

      foreach ($section in $allChecksBySection.Keys) {
        # --- build your checksInSection exactly as you had it ---
        $sectionHtml = $allChecksBySection[$section]
        $checkIds = [regex]::Matches($sectionHtml, "<h2 id='([^']+)'")            | ForEach-Object { $_.Groups[1].Value }
        $checkNames = [regex]::Matches($sectionHtml, "<h2 id='[^']+'>\s*[^-]+-\s*([^<]+)") | ForEach-Object { $_.Groups[1].Value.Trim() }
        $checksInSection = for ($i = 0; $i -lt [Math]::Min($checkIds.Count, $checkNames.Count); $i++) {
          @{ Id = $checkIds[$i]; Name = $checkNames[$i] }
        }

        # pick tab by mapping or fallback
        if ($knownSections -contains $section) {
          $navSection = $sectionToNavMap[$section]
        }
        else {
          $navSection = 'Custom Checks'
        }

        # accumulate nav‑items
        if (-not $customNavItems[$navSection]) { $customNavItems[$navSection] = @() }
        $customNavItems[$navSection] += $checksInSection

        # store the per‑section HTML
        $varName = "collapsible$($section -replace '[^\w]','')Html"
        if (Get-Variable -Name $varName -Scope Script -ErrorAction SilentlyContinue) {
          Set-Variable -Name $varName -Value ((Get-Variable $varName -ValueOnly) + "`n" + $sectionHtml)
        }
        else {
          Set-Variable -Name $varName -Value $sectionHtml
        }
      }

      # now build the Custom‑Checks tab only from that one bucket
      if ($customNavItems['Custom Checks'] -and $customNavItems['Custom Checks'].Count) {
        $snippets = foreach ($chk in $customNavItems['Custom Checks']) {
          $htmlVar = "collapsible$($chk.Id -replace '[^\w]','')Html"
          $s = Get-Variable -Name $htmlVar -ValueOnly -ErrorAction SilentlyContinue
          if ($s -match '<tr>.*?<td>.*?</td>.*?</tr>') { $s }
        }
        if ($snippets.Count) {
          $collapsibleCustomChecksHtml = $snippets -join "`n`n"
          $hasCustomChecks = $true
        }
      }

      continue
    }

    $pre = ""
    if ($html -match '^\s*<p>.*?</p>') {
      $pre = $matches[0]
      $html = $html -replace [regex]::Escape($pre), ""
    }
    elseif ($html -match '^\s*[^<]+$') {
      $lines = $html -split "`n", 2
      $pre = "<p>$($lines[0].Trim())</p>"
      $html = if ($lines.Count -gt 1) { $lines[1] } else { "" }
    }
    else {
      $pre = "<p>⚠️ $($check.Id) Report</p>"
    }

    $hasIssues = $html -match '<tr>.*?<td>.*?</td>.*?</tr>' -and $html -notmatch 'No data available'

    $content = if ($noFindings) {
      "$pre`n"
    }
    else {
      "$pre`n" + (ConvertToCollapsible -Id $check.Id -defaultText $defaultText -content $html)
    }

    Set-Variable -Name ("collapsible" + $check.Id + "Html") -Value $content
  }

  $clusterSummaryText = $clusterSummaryRaw -join "`n"
  function Extract-Metric($label, $data) {
    if ($data -match "$label\s*:\s*([\d]+)") { [int]$matches[1] } else { "0" }
  }
  $clusterName = "Unknown"
  $k8sVersion = "Unknown"

  $clusterScore = Get-ClusterHealthScore -Checks $checkScoreList
  $scoreColor = if ($clusterScore -ge 80) {
    "#4CAF50"
  }
  elseif ($clusterScore -ge 50) {
    "#FF9800"
  }
  else {
    "#F44336"
  }

  # Cluster Health Score Bar
  $scoreBarHtml = @"
<div class="score-container">
  <h2 class="cluster-health-score">Cluster Health Score</h2>
  <p>Score: <strong>$clusterScore / 100</strong></p>
  <div class="progress-bar" style="--cluster-score: $clusterScore;" role="progressbar" aria-label="Cluster Health Score: $clusterScore out of 100">
    <div class="progress" style="width: 0%;">
      <span class="progress-text">$clusterScore%</span>
    </div>
  </div>
  <p style="margin-top:10px; font-size:16px;">This score is calculated from key checks across nodes, workloads, security, and configuration best practices. A higher score means fewer issues and better adherence to Kubernetes standards.</p>
</div>
"@

  $totalChecks = $checkStatusList.Count
  $passedChecks = ($checkStatusList | Where-Object { $_.Status -eq 'Passed' }).Count

  if ($aks) {
    $totalChecks += $aksTotal
    $passedChecks += $aksPass
  }

  $healthStatusHtml = @"
<div class="health-status">
  <h2>Passed / Failed Checks</h2>
  <div class="status-container">
    <span class="status-text">
      <span class="count-up" data-count="$passedChecks">0</span>/<span class="count-up" data-count="$totalChecks">0</span> Passed
    </span>
    <span class="status-chip"></span>
  </div>
  <p style="margin-top:10px; font-size:16px;">This shows the number of health checks that passed out of the total checks performed across the cluster. A higher pass rate indicates better overall cluster health.</p>
</div>
"@

  for ($i = 0; $i -lt $clusterSummaryRaw.Count; $i++) {
    $line = [string]$clusterSummaryRaw[$i] -replace "`r", "" -replace "`n", ""
    if ($line -match "Cluster Name\s*$") { $clusterName = [string]$clusterSummaryRaw[$i + 2] -replace "`r", "" -replace "`n", "" }
    if ($line -match "Kubernetes Version\s*$") { $k8sVersion = [string]$clusterSummaryRaw[$i + 2] -replace "`r", "" -replace "`n", "" }
  }
  $compatibilityCheck = if ($clusterSummaryText -match "⚠️\s+(Cluster is running an outdated version:[^\n]+)") { $matches[1].Trim(); $compatibilityClass = "warning" }
  elseif ($clusterSummaryText -match "✅ Cluster is up to date \((.*?)\)") { "✅ Cluster is up to date ($matches[1])"; $compatibilityClass = "healthy" }
  else { "Unknown"; $compatibilityClass = "unknown" }
  $totalNodes = Extract-Metric "🚀 Nodes" $clusterSummaryText
  $healthyNodes = Extract-Metric "🟩 Healthy" $clusterSummaryText
  $issueNodes = Extract-Metric "🟥 Issues" $clusterSummaryText
  $totalPods = Extract-Metric "📦 Pods" $clusterSummaryText
  $runningPods = Extract-Metric "🟩 Running" $clusterSummaryText
  $failedPods = Extract-Metric "🟥 Failed" $clusterSummaryText
  $totalRestarts = Extract-Metric "🔄 Restarts" $clusterSummaryText
  $warnings = Extract-Metric "🟨 Warnings" $clusterSummaryText
  $critical = Extract-Metric "🟥 Critical" $clusterSummaryText
  $pendingPods = Extract-Metric "⏳ Pending Pods" $clusterSummaryText
  $stuckPods = Extract-Metric "⚠️ Stuck Pods" $clusterSummaryText
  $jobFailures = Extract-Metric "📉 Job Failures" $clusterSummaryText
  $eventWarnings = Extract-Metric "⚠️ Warnings" $clusterSummaryText
  $eventErrors = Extract-Metric "❌ Errors" $clusterSummaryText
  $podAvg = if ($clusterSummaryText -match "📊 Pod Distribution: Avg: ([\d.]+)") { $matches[1] } else { "0" }
  $podMax = if ($clusterSummaryText -match "Max: ([\d.]+)") { $matches[1] } else { "0" }
  $podMin = if ($clusterSummaryText -match "Min: ([\d.]+)") { $matches[1] } else { "0" }
  $podTotalNodes = if ($clusterSummaryText -match "Total Nodes: ([\d]+)") { $matches[1] } else { "0" }
  $cpuUsage = if ($clusterSummaryText -match "🖥  CPU Usage:\s*([\d.]+)%") { [double]$matches[1] } else { 0 }
  $cpuStatus = if ($clusterSummaryText -match "🖥  CPU Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }
  $memUsage = if ($clusterSummaryText -match "💾 Memory Usage:\s*([\d.]+)%") { [double]$matches[1] } else { 0 }
  $memStatus = if ($clusterSummaryText -match "💾 Memory Usage:.*(🟩 Normal|🟡 Warning|🔴 Critical)") { $matches[1] } else { "Unknown" }

  $today = (Get-Date).ToUniversalTime().ToString("MMMM dd, yyyy HH:mm:ss 'UTC'")
  $year = (Get-Date).ToUniversalTime().ToString("yyyy")
  $thresholds = Get-KubeBuddyThresholds -Silent
  $excludedNamespaces = Get-ExcludedNamespaces -Silent
  $errorClass = if ($eventErrors -ge $thresholds.event_errors_critical) { "critical" } elseif ($eventErrors -ge $thresholds.event_errors_warning) { "warning" } else { "normal" }
  $warningClass = if ($eventWarnings -ge $thresholds.event_warnings_critical) { "critical" } elseif ($eventWarnings -ge $thresholds.event_warnings_warning) { "warning" } else { "normal" }
  $cpuClass = if ($cpuUsage -ge $thresholds.cpu_critical) { "critical" } elseif ($cpuUsage -ge $thresholds.cpu_warning) { "warning" } else { "normal" }
  $memClass = if ($memUsage -ge [double]$thresholds.mem_critical) { "critical" } elseif ($memUsage -ge [double]$thresholds.mem_warning) { "warning" } else { "normal" }

  # Initialize Prometheus HTML content
  $clusterMetricsHtml = ""
  $nodeMetricsHtml = ""
  if ($KubeData.PrometheusMetrics -and $KubeData.PrometheusMetrics.NodeCpuUsagePercent) {
    Write-Host "📊 Generating Prometheus metrics for Summary and Nodes tabs..." -ForegroundColor Cyan

    # Cluster Metrics for Summary Tab
    $avgCpu = [math]::Round(($KubeData.PrometheusMetrics.NodeCpuUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } } | Measure-Object -Average).Average, 2)
    $avgMem = [math]::Round(($KubeData.PrometheusMetrics.NodeMemoryUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } } | Measure-Object -Average).Average, 2)
    $cpuClassProm = if ($avgCpu -ge $thresholds.cpu_critical) { "critical" } elseif ($avgCpu -ge $thresholds.cpu_warning) { "warning" } else { "normal" }
    $memClassProm = if ($avgMem -ge $thresholds.mem_critical) { "critical" } elseif ($avgMem -ge $thresholds.mem_warning) { "warning" } else { "normal" }

    # Aggregate CPU chart data (average across nodes)
    $cpuChartData = $KubeData.PrometheusMetrics.NodeCpuUsagePercent | ForEach-Object {
      $_.values | ForEach-Object {
        [PSCustomObject]@{
          timestamp = [int64]($_[0] * 1000)  # Convert seconds to milliseconds
          value     = [double]$_[1]
        }
      }
    } | Group-Object timestamp | ForEach-Object {
      [PSCustomObject]@{
        timestamp = $_.Name
        value     = [math]::Round(($_.Group | Measure-Object -Property value -Average).Average, 2)
      }
    } | Sort-Object timestamp
    $cpuChartJson = if ($cpuChartData) { $cpuChartData | ConvertTo-Json -Compress } else { "[]" }

    # Aggregate Memory chart data (average across nodes)
    $memChartData = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent | ForEach-Object {
      $_.values | ForEach-Object {
        [PSCustomObject]@{
          timestamp = [int64]($_[0] * 1000)
          value     = [double]$_[1]  # Keep as percentage
        }
      }
    } | Group-Object timestamp | ForEach-Object {
      [PSCustomObject]@{
        timestamp = $_.Name
        value     = [math]::Round(($_.Group | Measure-Object -Property value -Average).Average, 2)
      }
    } | Sort-Object timestamp
    $memChartJson = if ($memChartData) { $memChartData | ConvertTo-Json -Compress } else { "[]" }

    $clusterMetricsHtml = @"
<h2>Cluster Health Metrics (Last 24h)
  <span class='tooltip'>
    <span class='info-icon'>i</span>
    <span class='tooltip-text'>Historical CPU and memory metrics from Prometheus, averaged over the last 24 hours.</span>
  </span>
</h2>
<div class='hero-metrics'>
  <div class='metric-card $cpuClassProm'>🖥 Avg CPU: <strong>$avgCpu%</strong><br><span>$(if ($cpuClassProm -eq 'normal') { 'Normal' } elseif ($cpuClassProm -eq 'warning') { 'Warning' } else { 'Critical' })</span></div>
  <div class='metric-card $memClassProm'>💾 Avg Memory: <strong>$avgMem%</strong><br><span>$(if ($memClassProm -eq 'normal') { 'Normal' } elseif ($memClassProm -eq 'warning') { 'Warning' } else { 'Critical' })</span></div>
</div>
<div class='chart-container'>
  <div class='chart-item'>
    <h3>Cluster CPU Usage (%)</h3>
    <canvas id='clusterCpuChart' data-values='$cpuChartJson'></canvas>
  </div>
  <div class='chart-item'>
    <h3>Cluster Memory Usage (%)</h3>
    <canvas id='clusterMemChart' data-values='$memChartJson'></canvas>
  </div>
</div>
"@

    # Node Metrics for Nodes Tab
    $nodeMetricsHtml = @"
<h2>Node Health Metrics
  <span class='tooltip'>
    <span class='info-icon'>i</span>
    <span class='tooltip-text'>Historical CPU and memory metrics per node from Prometheus, averaged over the last 24 hours.</span>
  </span>
</h2>
<table class='table-container'>
  <thead>
    <tr><th>Node</th><th>Avg CPU (24h)</th><th>Avg Memory (24h)</th><th>CPU Trend</th></tr>
  </thead>
  <tbody>
"@
    foreach ($node in $KubeData.Nodes.items) {
      $nodeName = $node.metadata.name
      $cpuMetrics = $KubeData.PrometheusMetrics.NodeCpuUsagePercent | Where-Object { $_.metric.instance -match $nodeName }
      $memMetrics = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent | Where-Object { $_.metric.instance -match $nodeName }
      $avgCpu = if ($cpuMetrics) { [math]::Round(($cpuMetrics.values | ForEach-Object { [double]$_[1] } | Measure-Object -Average).Average, 2) } else { "N/A" }
      $avgMem = if ($memMetrics) { [math]::Round(($memMetrics.values | ForEach-Object { [double]$_[1] } | Measure-Object -Average).Average, 2) } else { "N/A" }
      $cpuValues = if ($cpuMetrics) { ($cpuMetrics.values | ForEach-Object { [double]$_[1] }) -join "," } else { "[]" }
      $cpuClass = if ($avgCpu -ne "N/A" -and $avgCpu -ge $thresholds.cpu_critical) { "critical" } elseif ($avgCpu -ne "N/A" -and $avgCpu -ge $thresholds.cpu_warning) { "warning" } else { "normal" }
      $memClass = if ($avgMem -ne "N/A" -and $avgMem -ge $thresholds.mem_critical) { "critical" } elseif ($avgMem -ne "N/A" -and $avgMem -ge $thresholds.mem_warning) { "warning" } else { "normal" }
      $nodeMetricsHtml += "<tr><td>$nodeName</td><td class='$cpuClass'>$($avgCpu -eq 'N/A' ? 'N/A' : "$avgCpu%")</td><td class='$memClass'>$($avgMem -eq 'N/A' ? 'N/A' : "$avgMem%")</td><td><canvas class='sparkline' data-values='[$cpuValues]'></canvas></td></tr>"
    }
    $nodeMetricsHtml += "</tbody></table>"
  }
  else {
    $clusterMetricsHtml = "<p class='warning'>⚠️ Prometheus metrics unavailable. Ensure Prometheus is configured.</p>"
    $nodeMetricsHtml = "<p class='warning'>⚠️ Prometheus metrics unavailable. Ensure Prometheus is configured.</p>"
  }

  if ($ExcludeNamespaces) {
    $excludedList = ($excludedNamespaces | ForEach-Object { "<span class='excluded-ns'>$_</span>" }) -join " • "
    $excludedNamespacesHtml = @"
<h2>Excluded Namespaces
<span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">These namespaces are excluded from analysis and reporting.</span></span>
</h2>
<p>$excludedList</p>
"@
  }
  else {
    $excludedNamespacesHtml = ""
  }

  $htmlTemplate = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>Kubernetes Cluster Report</title>
<link rel='icon' href='https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/assets/images/favicon.ico' type='image/x-icon'>
<link href='https://fonts.googleapis.com/icon?family=Material+Icons' rel='stylesheet'>
<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
<script src='https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js'></script>
<script src='https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js'></script>
    <style>
        $cssContent
    </style>
</head>
<body>
<div class="wrapper">
  <div class="main-content">
<div class="header">
  <div class="header-inner">
    <div class="header-top">
      <div>
        <span>Kubernetes Cluster Report: $ClusterName</span>
        <br>
        <span style="font-size: 12px;">
          Powered by 
          <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy Logo" style="height: 70px; vertical-align: middle;">
        </span>
      </div>
      <div style="text-align: right; font-size: 13px; line-height: 1.4;">
        <div>Generated on: <strong>$today</strong></div>
        <div>
          Created by 
          <a href="https://kubedeck.io" target="_blank" style="color: #ffffff; text-decoration: underline;">
            🌐 KubeDeck.io
          </a>
        </div>
        <div id="printContainer" style="margin-top: 4px;">
          <button id="savePdfBtn">📄 Save as PDF</button>
        </div>
      </div>
    </div>
    <ul class="tabs">
      <li class="tab active" data-tab="summary" data-tooltip="Summary">Summary</li>
      <li class="tab" data-tab="nodes" data-tooltip="Nodes">Nodes</li>
      <li class="tab" data-tab="namespaces" data-tooltip="Namespaces">Namespaces</li>
      <li class="tab" data-tab="workloads" data-tooltip="Workloads">Workloads</li>
      <li class="tab" data-tab="pods" data-tooltip="Pods">Pods</li>
      <li class="tab" data-tab="jobs" data-tooltip="Jobs">Jobs</li>
      <li class="tab" data-tab="networking" data-tooltip="Networking">Networking</li>
      <li class="tab" data-tab="storage" data-tooltip="Storage">Storage</li>
      <li class="tab" data-tab="configuration" data-tooltip="Configuration">Configuration</li>
      <li class="tab" data-tab="security" data-tooltip="Security">Security</li>
      <li class="tab" data-tab="events" data-tooltip="Kubernetes Events">Kubernetes Events</li>
      $(if ($hasCustomChecks) { '<li class="tab" data-tab="customChecks" data-tooltip="Custom Checks">Custom Checks</li>' })
      $(if ($aks) { '<li class="tab" data-tab="aks" data-tooltip="AKS Best Practices">AKS Best Practices</li>' })
    </ul>
  </div>
</div>
<div id="navDrawer" class="nav-drawer">
  <div class="nav-header">
    <h3>Menu</h3>
    <button id="navClose" class="nav-close">×</button>
  </div>
  <ul class="nav-items"></ul>
</div>
<div id="navScrim" class="nav-scrim"></div>
<button id="menuFab">☰</button>
<div class="tab-content active" id="summary">
  <div class="container">
    <h1 id="Health">Cluster Overview</h1>
    <p><strong>Cluster Name:</strong> $ClusterName</p>
    <div class="cluster-health">
      <div class="health-score">
        $scoreBarHtml
      </div>
      <div class="api-summary">
        <h2>API Server Health</h2>
        $apiHealthHtml
      </div>
      <div class="health-status">
        $healthStatusHtml
      </div>
    </div>
  </div>
  <div class="container">
    <h1 id="summary">Cluster Summary</h1>
    <p><strong>Cluster Name:</strong> $ClusterName</p>
    <p><strong>Kubernetes Version:</strong> $k8sVersion</p>
    <div class="compatibility $compatibilityClass"><strong>$compatibilityCheck</strong></div>
    <h2>Cluster Metrics Summary <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Summary of metrics including node and pod counts, warnings, and issues.</span></span></h2>
    <table>
      <tr><td>🚀 Nodes: $totalNodes</td><td>🟩 Healthy: $healthyNodes</td><td>🟥 Issues: $issueNodes</td></tr>
      <tr><td>📦 Pods: $totalPods</td><td>🟩 Running: $runningPods</td><td>🟥 Failed: $failedPods</td></tr>
      <tr><td>🔄 Restarts: $totalRestarts</td><td>🟨 Warnings: $warnings</td><td>🟥 Critical: $critical</td></tr>
      <tr><td>⏳ Pending Pods: $pendingPods</td><td>🟡 Waiting: $pendingPods</td></tr>
      <tr><td>⚠️ Stuck Pods: $stuckPods</td><td>❌ Stuck: $stuckPods</td></tr>
      <tr><td>📉 Job Failures: $jobFailures</td><td>🔴 Failed: $jobFailures</td></tr>
    </table>
    <h2>Pod Distribution <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Average, min, and max pods per node and total node count.</span></span></h2>
    <table>
      <tr><td>Avg: <strong>$podAvg</strong></td><td>Max: <strong>$podMax</strong></td><td>Min: <strong>$podMin</strong></td><td>Total Nodes: <strong>$podTotalNodes</strong></td></tr>
    </table>
    <h2>Resource Usage 
      <span class="tooltip">
        <span class="info-icon">i</span>
        <span class="tooltip-text">
          Cluster-wide CPU and memory usage. This reflects a snapshot taken at report generation time.
        </span>
      </span>
    </h2>
    <p style="font-size: 14px; color: #666; margin-top: -10px;">🕒 Snapshot time: <strong>$today</strong></p>
    <div class="hero-metrics">
      <div class="metric-card $cpuClass">🖥 CPU: <strong>$cpuUsage%</strong><br><span>$cpuStatus</span></div>
      <div class="metric-card $memClass">💾 Memory: <strong>$memUsage%</strong><br><span>$memStatus</span></div>
    </div>
    $clusterMetricsHtml
    <h2>Cluster Events <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Summary of recent warning and error events.</span></span></h2>
    <div class="hero-metrics">
      <div class="metric-card $errorClass" onclick="switchTab('events')" style="cursor: pointer;" title="Click to view Kubernetes Events">
        ❌ Errors: <strong>$eventErrors</strong>
      </div>
      <div class="metric-card $warningClass" onclick="switchTab('events')" style="cursor: pointer;" title="Click to view Kubernetes Events">
        ⚠️ Warnings: <strong>$eventWarnings</strong>
      </div>
    </div>
    $excludedNamespacesHtml
  </div>
</div>
<div class="tab-content" id="nodes">
  <div class="container">
    <h1>Node Conditions & Resources</h1>
    $nodeMetricsHtml
    <div class="table-container">$collapsibleNodesHtml</div>
  </div>
</div>
<div class="tab-content" id="namespaces">
  <div class="container">
    <h1>Namespaces</h1>
    <div class="table-container">$collapsibleNamespacesHtml</div>
  </div>
</div>
<div class="tab-content" id="workloads">
  <div class="container">
    <h1>Workloads</h1>
    <div class="table-container">$collapsibleWorkloadsHtml</div>
  </div>
</div>
<div class="tab-content" id="pods">
  <div class="container">
    <h1>Pods</h1>
    <div class="table-container">$collapsiblePodsHtml</div>
  </div>
</div>
<div class="tab-content" id="jobs">
  <div class="container">
    <h1>Jobs</h1>
    <div class="table-container">$collapsibleJobsHtml</div>
  </div>
</div>
<div class="tab-content" id="networking">
  <div class="container">
    <h1>Networking</h1>
    <div class="table-container">$collapsibleNetworkingHtml</div>
  </div>
</div>
<div class="tab-content" id="storage">
  <div class="container">
    <h1>Storage</h1>
    <div class="table-container">$collapsibleStorageHtml</div>
  </div>
</div>
<div class="tab-content" id="configuration">
  <div class="container">
    <h1>Configuration Hygiene</h1>
    <div class="table-container">$collapsibleConfigurationHygieneHtml</div>
  </div>
</div>
<div class="tab-content" id="security">
  <div class="container">
    <h1>Security</h1>
    <div class="table-container">$collapsibleSecurityHtml</div>
  </div>
</div>
<div class="tab-content" id="events">
  <div class="container">
    <h1>Kubernetes Warning Events</h1>
    <div class="table-container">$collapsibleKubernetesEventsHtml</div>
  </div>
</div>
$(if ($hasCustomChecks) {
  @"
<div class="tab-content" id="customChecks">
  <div class="container">
    <h1>Custom Checks</h1>
    <div class="table-container">$collapsibleCustomChecksHtml</div>
  </div>
</div>
"@
})
$(if ($aks) {
  @"
<div class="tab-content" id="aks">
  $aksHealthCheck
</div>
"@
})
</div>
<footer class="footer">
  <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy Logo" class="logo">
  <p><strong>Report generated by KubeBuddy $version</strong> on $today</p>
  <p>© $year KubeBuddy | <a href="https://kubedeck.io" target="_blank">KubeDeck.io</a></p>
  <p><em>This report is a snapshot of the cluster state at the time of generation. Always verify configurations before making critical decisions.</em></p>
</footer>
 </div>
<a href="#top" id="backToTop">Back to Top</a>
<script>
  $jsContent
</script>
</body>
</html>
"@
  $htmlTemplate | Set-Content $outputPath
}