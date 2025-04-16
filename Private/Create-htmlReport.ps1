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

  # Path to report-scripts.js in the module directory
  $jsPath = Join-Path $PSScriptRoot "html/report-scripts.js"

  # Read the JavaScript content
  if (Test-Path $jsPath) {
    $jsContent = Get-Content -Path $jsPath -Raw
  }
  else {
    $jsContent = "// Error: report-scripts.js not found at $jsPath"
    Write-Warning "report-scripts.js not found at $jsPath. HTML features may not work."
  }

  Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan
  Write-Host -NoNewline "`n🤖 Fetching Cluster Information..." -ForegroundColor Yellow
  $clusterSummaryRaw = Show-ClusterSummary -Html -KubeData:$KubeData *>&1
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
    @{ Id = "allChecks"; Cmd = { Invoke-CustomKubectlChecks -Html -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } }
  )

  $customNavItems = @{}
  $checkStatusList = @()


  foreach ($check in $checks) {
    $html = & $check.Cmd
    if (-not $html) {
      $html = "<p>No data available for $($check.Id).</p>"
    }
    # # Record pass/fail status
    # $status = if ($html -match '✅') { 'Passed' } else { 'Failed' }
    # $checkStatusList += [pscustomobject]@{
    #   Id     = $check.Id
    #   Status = $status
    # }

    # Inject custom checks into sections as before...
    if ($check.Id -eq "allChecks" -and $html -is [hashtable]) {
      $allChecksBySection = $html.HtmlBySection
      $allCheckstatusList = $html.StatusList
      $checkStatusList += $allCheckstatusList


      foreach ($section in $allChecksBySection.Keys) {
        $sanitizedId = $section -replace '[^\w]', ''
        $varName = "collapsible" + $sanitizedId + "Html"
        $sectionHtml = $allChecksBySection[$section]
        # Inject into appropriate section variable for rendering in correct tab
        $htmlVarName = "collapsible" + ($section -replace '[^\w]', '') + "Html"
        if (Get-Variable -Name $htmlVarName -ErrorAction SilentlyContinue) {
          Set-Variable -Name $htmlVarName -Value ((Get-Variable -Name $htmlVarName -ValueOnly) + "`n" + $sectionHtml)
        }
        else {
          Set-Variable -Name $htmlVarName -Value $sectionHtml
        }
        $checkIds = [regex]::Matches($sectionHtml, "<h2 id=''([^'']+)'") | ForEach-Object { $_.Groups[1].Value }
        $checkNames = [regex]::Matches($sectionHtml, "<h2 id='[^']+'>\s*[^-]+\s*-\s*([^<]+)\s*(?:<span.*?</span>)?\s*</h2>") | ForEach-Object { $_.Groups[1].Value }

        $checksInSection = for ($i = 0; $i -lt [Math]::Min($checkIds.Count, $checkNames.Count); $i++) {
          @{
            Id   = $checkIds[$i]
            Name = $checkNames[$i].Trim()
          }
        }

        $navSection = $sectionToNavMap[$section]
        if (-not $navSection) { $navSection = "Custom Checks" }
        if (-not $customNavItems[$navSection]) { $customNavItems[$navSection] = @() }
        $customNavItems[$navSection] += $checksInSection

        if (Get-Variable -Name $varName -Scope "Script" -ErrorAction SilentlyContinue) {
          Set-Variable -Name $varName -Value (@((Get-Variable -Name $varName -ValueOnly) , $sectionHtml) -join "`n")
        }
        else {
          Set-Variable -Name $varName -Value $sectionHtml
        }

        # foreach ($section in $sectionToNavMap.Keys) {
        #   if ($check.Id -match $section -or ($section -eq "Configuration Hygiene" -and $check.Id -match "Configuration")) {
        #     if (-not $customNavItems[$section]) { $customNavItems[$section] = @() }
        #     $customNavItems[$section] += @{
        #       Id   = $check.Id
        #       Name = ($check.Id -replace '([a-z])([A-Z])', '$1 $2') -replace '-', ' ' -replace '\s+', ' '
        #     }
        #     break
        #   }
        # }
      }
      continue
    }

    if ($check.Id -eq "eventSummary") {
      $summaryHtml = $html.SummaryHtml
      $eventsHtml = $html.EventsHtml
      $summaryPre = if ($summaryHtml -match '^\s*<p>.*?</p>') { $matches[0] } else { "<p>⚠️ Warning Summary Report</p>" }
      $summaryContent = $summaryHtml -replace [regex]::Escape($summaryPre), ""
      $summaryHasIssues = $summaryContent -match '<tr>.*?<td>.*?</td>.*?</tr>' -and $summaryContent -notmatch 'No data available'
      $summaryNoFindings = $summaryPre -match '✅'
      $summaryRecommendation = if ($summaryHasIssues) {
        $recommendationText = @"
<div class="recommendation-content">
  <h4>🛠️ Address Warning Events</h4>
  <ul>
    <li><strong>Correlate:</strong> Match events to resources (<code>kubectl describe <resource> <name></code>).</li>
    <li><strong>Root Cause:</strong> Investigate logs or metrics for warnings.</li>
    <li><strong>Fix:</strong> Adjust resources or configs based on event type.</li>
    <li><strong>Monitor:</strong> Set up alerts for recurring warnings.</li>
  </ul>
</div>
"@
        @"
<div class="recommendation-card">
  <details style='margin-bottom: 10px;'>
      <summary style='color: #0071FF; font-weight: bold; font-size: 14px; padding: 10px; background: #E3F2FD; border-radius: 4px 4px 0 0;'>Recommendations</summary>
      $recommendationText
  </details>
</div>
<div style='height: 15px;'></div>
"@
      }
      else { "" }

      $summaryContentFinal = if ($summaryNoFindings) {
        "$summaryPre`n"
      }
      else {
        "$summaryPre`n" + (ConvertToCollapsible -Id "eventSummaryWarnings" -defaultText "Show Warning Summary" -content "$summaryRecommendation`n$summaryContent")
      }
      Set-Variable -Name "collapsibleEventSummaryWarningsHtml" -Value $summaryContentFinal

      $eventsPre = if ($eventsHtml -match '^\s*<p>.*?</p>') { $matches[0] } else { "<p>⚠️ Full Warning Event Log</p>" }
      $eventsContent = $eventsHtml -replace [regex]::Escape($eventsPre), ""
      $eventsHasIssues = $eventsContent -match '<tr>.*?<td>.*?</td>.*?</tr>' -and $eventsContent -notmatch 'No data available'
      $eventsNoFindings = $eventsPre -match '✅'
      $eventsRecommendation = if ($eventsHasIssues) {
        $recommendationText = @"
<div class="recommendation-content">
  <h4>🛠️ Address Warning Events</h4>
  <ul>
    <li><strong>Correlate:</strong> Match events to resources (<code>kubectl describe <resource> <name></code>).</li>
    <li><strong>Root Cause:</strong> Investigate logs or metrics for warnings/errors.</li>
    <li><strong>Fix:</strong> Adjust resources or configs as needed.</li>
    <li><strong>Monitor:</strong> Set up alerts for recurring events.</li>
  </ul>
</div>
"@
        @"
<div class="recommendation-card">
  <details style='margin-bottom: 10px;'>
      <summary style='color: #0071FF; font-weight: bold; font-size: 14px; padding: 10px; background: #E3F2FD; border-radius: 4px 4px 0 0;'>Recommendations</summary>
      $recommendationText
  </details>
</div>
<div style='height: 15px;'></div>
"@
      }
      else { "" }

      $eventsContentFinal = if ($eventsNoFindings) {
        "$eventsPre`n"
      }
      else {
        "$eventsPre`n" + (ConvertToCollapsible -Id "eventSummaryFullLog" -defaultText "Show Full Warning Event Log" -content "$eventsRecommendation`n$eventsContent")
      }
      Set-Variable -Name "collapsibleEventSummaryFullLogHtml" -Value $eventsContentFinal

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
  $clusterScore = Get-ClusterHealthScore -Checks $checkStatusList
  $scoreColor = if ($clusterScore -ge 80) {
    "#4CAF50"
  }
  elseif ($clusterScore -ge 50) {
    "#FF9800"
  }
  else {
    "#F44336"
  }
  
  $scoreBarHtml = @"
<div class="score-container">
  <p>Score: <strong>$clusterScore / 100</strong></p>
  <div class="progress-bar" style="--cluster-score: $clusterScore%; --score-color: $scoreColor;">
    <div class="progress" style="width: $clusterScore%;">
      <span class="progress-text">$clusterScore%</span>
    </div>
  </div>
  <p style="margin-top:10px; font-size:16px;">This score is calculated from key checks across nodes, workloads, security, and configuration best practices.
A higher score means fewer issues and better adherence to Kubernetes standards.</p>
</div>
"@

  $totalChecks = $checkStatusList.Count
  $passedChecks = ($checkStatusList | Where-Object { $_.Status -eq 'Passed' }).Count

  # Add AKS if enabled
  if ($aks) {
    $totalChecks += $aksTotal
    $passedChecks += $aksPass
  }

  $issuesChecks = $totalChecks - $passedChecks
  $passedPercent = if ($totalChecks -gt 0) { [math]::Round(($passedChecks / $totalChecks) * 100, 2) } else { 0 }

  $donutStroke = $scoreColor

  $pieChartHtml = @"
<svg class="pie-chart donut" width="120" height="120" viewBox="0 0 36 36" style="--percent: $passedPercent">
  <circle class="donut-ring"
          cx="18" cy="18" r="15.9155"
          stroke="#ECEFF1"
          stroke-width="4"
          fill="transparent"/>
  <circle class="donut-segment"
          cx="18" cy="18" r="15.9155"
          stroke="$donutStroke"
          stroke-width="4"
          stroke-dasharray="$passedPercent, 100"
          stroke-dashoffset="25"
          stroke-linecap="round"
          fill="transparent"
          style="transition: stroke-dasharray 1s ease;" />
<text x="18" y="20.5" text-anchor="middle" dominant-baseline="middle" font-size="8" fill="#37474F"
  transform="rotate(90 18 18)">
  $passedChecks/$totalChecks
</text>
  <circle id="pulseDot" r="0.6" fill="$donutStroke" style="opacity: 0;" />
</svg>
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

  # Updated HTML template using Tabs
  $htmlTemplate = @"
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1.0'>
  <title>Kubernetes Cluster Report</title>
  <link rel='icon' href='https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/assets/images/favicon.ico' type='image/x-icon'>
  <link href='https://fonts.googleapis.com/icon?family=Material+Icons' rel='stylesheet'>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;700&display=swap');

    html { scroll-behavior: smooth; }

    body { 
        font-family: 'Roboto', sans-serif; 
        margin: 0; 
        padding: 0; 
        background: #eceff1; 
        color: #37474f; 
    }

    .header { 
        background: linear-gradient(90deg, #005ad1, #0071FF); 
        color: white; 
        display: flex; 
        flex-direction: column;
        justify-content: space-between; 
        align-items: center; 
        padding: 10px 24px; 
        font-weight: bold; 
        font-size: 24px; 
        box-shadow: 0 4px 12px rgba(0,0,0,0.2); 
        position: relative; 
        top: auto; 
        z-index: auto; 
    }
    .header-top {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
      /* Responsive Header Inner Container */
      .header-inner {
        width: 100%;
        max-width: 1350px; /* Adjust as needed */
        margin: 0 auto;
      }
      .header .tabs {
      list-style: none;
      margin: 10px 0 0 0;
      padding: 0;
      display: flex;
      overflow-x: auto;
      border-bottom: 1px solid rgba(255,255,255,0.3);
    }

    .header .tabs li {
      color: #fff;
      padding: 10px 20px;
      cursor: pointer;
      font-weight: bold;
      font-size: 12px;
      white-space: nowrap;
    }

    .header .tabs li.active {
      border-bottom: 3px solid #fff;
    }

    .header .nav-toggle { 
        cursor: pointer; 
        font-size: 28px; 
        color: #fff; 
    }

    .header .logo { 
        height: 44px; 
        margin-right: 12px; 
    }

    .container { 
        max-width: 1350px; 
        margin: 20px auto; 
        background: white; 
        padding: 20px; 
        border-radius: 12px; 
        box-shadow: 0 6px 15px rgba(0, 0, 0, 0.1); 
    }

    .compatibility { 
        padding: 12px; 
        border-radius: 8px; 
        font-weight: bold; 
        text-align: center; 
        color: #ffffff; 
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2); 
    }

    .warning { background: #ffeb3b; }
    .healthy { background: #4CAF50; }
    .unknown { background: #9E9E9E; }

    .table-container { 
        overflow-x: auto; 
        width: 100%; 
        max-width: 100%; 
    }

    table { 
        width: 100%; 
        border-collapse: separate; 
        border-spacing: 0; 
        margin: 20px 0; 
        font-size: 14px; 
        text-align: left; 
        background: #fff; 
        border-radius: 8px; 
        box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        border-left: 1px solid #e0e0e0; 
        border-right: 1px solid #e0e0e0; 
    }

    th { 
        background-color: #0071FF; 
        color: white; 
        padding: 12px; 
        font-weight: 500; 
        position: relative; 
        cursor: pointer; 
        white-space: nowrap; 
        overflow: hidden; 
        text-overflow: ellipsis; 
    }

    th:hover { 
        background-color: #005ad1; 
    }

    th::after { 
        content: ''; 
        display: inline-block; 
        margin-left: 5px; 
        vertical-align: middle; 
    }

    td { 
        padding: 12px; 
        border-bottom: 1px solid #e0e0e0; 
    }

    tr:last-child td { 
        border-bottom: none; 
    }

    tr:hover td { 
        background: #f5f5f5; 
        transition: background 0.2s; 
    }

    th:first-child { 
        border-top-left-radius: 8px; 
    }

    th:last-child { 
        border-top-right-radius: 8px; 
    }

    td:first-child { 
        border-left: none; 
    }

    td:last-child { 
        border-right: none; 
    }

    table a { 
        color: #0071FF; 
        text-decoration: none; 
        font-weight: 500; 
    }

    table a:hover { 
        text-decoration: underline; 
        color: #005ad1; 
    }

    #backToTop { 
        position: fixed; 
        bottom: 20px; 
        right: 20px; 
        background: #0071FF; 
        color: #fff; 
        padding: 10px 15px; 
        border-radius: 25px; 
        text-decoration: none; 
        font-size: 14px; 
        font-weight: bold; 
        box-shadow: 0 4px 12px rgba(0,0,0,0.3); 
        display: none; 
        transition: opacity 0.3s ease; 
    }

    #backToTop:hover { 
        background: #005ad1; 
    }

    #printContainer { 
        text-align: right; 
        margin-bottom: 15px; 
    }

    #printContainer button { 
        background: #0071FF; 
        color: white; 
        padding: 10px 15px; 
        border: none; 
        cursor: pointer; 
        font-size: 16px; 
        border-radius: 8px; 
        transition: background 0.3s; 
    }

    #printContainer button:hover { 
        background: #005ad1; 
    }

    #savePdfBtn { 
        background: #0071FF; 
        color: white; 
        padding: 8px 12px; 
        font-size: 14px; 
        font-weight: bold; 
        border: none; 
        cursor: pointer; 
        border-radius: 8px; 
        margin-top: 10px; 
        transition: background 0.3s; 
    }

    #savePdfBtn:hover { 
        background: #005ad1; 
    }

    .excluded-ns { 
        padding: 2px 6px; 
        background-color: #eee; 
        border-radius: 4px; 
        margin-right: 4px; 
        display: inline-block; 
    }

    .nav-item a,
    .header .tabs li,
    .nav-item details summary {
      position: relative; /* required for ripple positioning */
      overflow: hidden;   /* keeps the ripple inside */
    }

    .nav-drawer { 
        position: fixed; 
        top: 0; 
        left: -280px; 
        width: 280px; 
        height: 100%; 
        background: linear-gradient(135deg, #f5f7fa, #ffffff); 
        box-shadow: 4px 0 12px rgba(0,0,0,0.2); 
        transition: left 0.3s ease-in-out; 
        z-index: 2000; 
        overflow-y: auto; 
    }

    .nav-drawer.open { 
        left: 0; 
    }

    .nav-scrim { 
        position: fixed; 
        top: 0; 
        left: 0; 
        width: 100%; 
        height: 100%; 
        background-color: rgba(0,0,0,0.4); 
        z-index: 1999; 
        display: none; 
    }

    .nav-scrim.open { 
        display: block; 
    }

    .nav-content { 
        padding: 20px; 
    }

    .nav-header { 
        padding: 20px; 
        border-bottom: 1px solid #e0e0e0; 
        display: flex; 
        justify-content: space-between; 
        align-items: center; 
        background: #0071FF; 
        color: #fff; 
    }

    .nav-header h3 { 
        margin: 0; 
        font-size: 24px; 
        font-weight: 700; 
    }

    .nav-close { 
        background: none; 
        border: none; 
        cursor: pointer; 
        font-size: 28px; 
        color: #fff; 
        transition: color 0.3s; 
    }

    .nav-close:hover { 
        color: #BBDEFB; 
    }

    .nav-items { 
        list-style: none; 
        padding: 0; 
        margin: 0; 
    }

    .nav-item { 
        position: relative; 
    }

    .nav-item a { 
        display: flex; 
        align-items: center; 
        padding: 12px 20px; 
        color: #37474f; 
        text-decoration: none; 
        font-size: 16px; 
        font-weight: 400; 
        transition: background-color 0.3s, color 0.3s; 
        border-radius: 6px; 
    }

    .nav-item a:hover { 
        background: #E3F2FD; 
        color: #005ad1; 
    }

    .nav-item .material-icons { 
        margin-right: 16px; 
        font-size: 22px; 
        color: #0071FF; 
    }

    .nav-item details { 
        margin: 5px 0; 
    }

    .nav-item details summary { 
        display: flex; 
        align-items: center; 
        padding: 12px 20px; 
        color: #37474f; 
        font-size: 16px; 
        font-weight: 500; 
        cursor: pointer; 
        transition: background-color 0.3s, color 0.3s; 
        border-radius: 6px; 
    }

    .nav-item details summary:hover { 
        background: #E3F2FD; 
        color: #005ad1; 
    }

    .nav-item details summary .material-icons { 
        margin-right: 16px; 
        font-size: 22px; 
        color: #0071FF; 
    }

    .nav-item details ul { 
        padding-left: 48px; 
        list-style: none; 
    }

    .nav-item details ul li a { 
        padding: 8px 20px; 
        font-size: 14px; 
        font-weight: 400; 
        color: #455A64; 
        border-radius: 6px; 
    }

    .nav-item details ul li a:hover { 
        background: #f0f4f8; 
        color: #0071FF; 
    }

    .ripple {
      position: absolute;
      background: rgba(0, 0, 0, 0.2);
      border-radius: 50%;
      transform: scale(0);
      animation: ripple-effect 600ms linear;
      pointer-events: none;
      width: 100px;
      height: 100px;
      margin-left: -50px;
      margin-top: -50px;
    }

    @keyframes ripple-effect {
      to {
        transform: scale(4);
        opacity: 0;
      }
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
        border-radius: 10px; 
        color: white; 
        font-size: 20px; 
        font-weight: bold; 
        min-width: 150px; 
        flex: 1; 
        margin: 10px; 
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1); 
    }

    .normal { background-color: #388e3c; }
    .warning { background-color: #ffa000; }
    .critical { background-color: #B71C1C; }
    .default { background-color: #0071FF; }

    .tooltip { 
        display: inline-block; 
        position: relative; 
        cursor: pointer; 
        margin-left: 8px; 
        color: #0071FF; 
        font-weight: bold; 
    }

    .tooltip .tooltip-text { 
        visibility: hidden; 
        width: 260px; 
        background-color: #0071FF; 
        color: #fff; 
        text-align: left; 
        border-radius: 6px; 
        padding: 8px; 
        position: absolute; 
        z-index: 10; 
        bottom: 125%; 
        left: 50%; 
        margin-left: -130px; 
        opacity: 0; 
        transition: opacity 0.3s; 
        font-size: 13px; 
    }

    .tooltip:hover .tooltip-text { 
        visibility: visible; 
        opacity: 1; 
    }

    .tooltip .tooltip-text::after { 
        content: ""; 
        position: absolute; 
        top: 100%; 
        left: 50%; 
        margin-left: -6px; 
        border-width: 6px; 
        border-style: solid; 
        border-color: #0071FF transparent transparent transparent; 
    }

    .info-icon { 
        display: inline-flex; 
        align-items: center; 
        justify-content: center; 
        font-size: 13px; 
        font-weight: bold; 
        width: 18px; 
        height: 18px; 
        border-radius: 50%; 
        border: 1px solid #0071FF; 
        color: #0071FF; 
        background-color: #ffffff; 
        font-family: sans-serif; 
        vertical-align: middle; 
        position: relative; 
        top: -1px; 
        line-height: 1; 
    }

    html, body {
        height: 100%;
        margin: 0;
    }
    .wrapper {
        display: flex;
        flex-direction: column;
        min-height: 100vh;
    }
    .main-content {
        flex: 1;
    }

    .footer { 
        background: linear-gradient(90deg, #263238, #37474f); 
        color: white; 
        text-align: center; 
        padding: 20px; 
        font-size: 14px; 
        position: relative; 
        z-index: 1000;
    }

    .footer a { 
        color: #80cbc4; 
        text-decoration: none; 
    }

    .footer a:hover { 
        text-decoration: underline; 
    }

    .footer .logo { 
        height: 30px; 
        margin-bottom: 10px; 
    }

    .recommendation-card { 
        margin-bottom: 10px; 
    }

    .recommendation-card details { 
        background: #fff; 
        border-radius: 8px; 
        box-shadow: 0 2px 6px rgba(0,0,0,0.1); 
    }

    .recommendation-card summary { 
        padding: 12px; 
        background: #E3F2FD; 
        border-radius: 8px 8px 0 0; 
    }

    .recommendation-card summary:hover { 
        background: #BBDEFB; 
    }

    .recommendation-content { 
        padding: 15px; 
        background: #f9f9f9; 
        border: 1px solid #BBDEFB; 
        border-top: none; 
        border-radius: 0 0 8px 8px; 
        color: #37474f; 
        line-height: 1.6; 
    }

    .recommendation-content h4 { 
        margin: 0 0 10px 0; 
        font-size: 16px; 
        color: #0071FF; 
    }

    .recommendation-content ul { 
        padding-left: 20px; 
        margin: 0; 
    }

    .recommendation-content li { 
        margin-bottom: 10px; 
    }

    .recommendation-content code { 
        background: #e0e0e0; 
        padding: 2px 4px; 
        border-radius: 4px; 
        font-family: 'Courier New', Courier, monospace; 
    }

    .table-pagination { 
        margin-top: 10px; 
        display: flex; 
        flex-wrap: wrap; 
        align-items: center; 
        gap: 10px; 
    }

    .table-pagination select, 
    .table-pagination button { 
        padding: 6px 12px; 
        border-radius: 6px; 
        border: 1px solid #ccc; 
        background: #f7f7f7; 
        cursor: pointer; 
    }

    .table-pagination button[disabled] { 
        opacity: 0.5; 
        cursor: not-allowed; 
    }

    .table-pagination .active { 
        font-weight: bold; 
        background: #0071FF; 
        color: white; 
    }

    #menuFab { 
        position: fixed; 
        bottom: 20px; 
        left: 20px; 
        width: 52px; 
        height: 52px; 
        background-color: #0071FF; 
        color: white; 
        border: none; 
        border-radius: 50%; 
        font-size: 24px; 
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3); 
        cursor: pointer; 
        z-index: 2001; 
        display: flex; 
        align-items: center; 
        justify-content: center; 
        transition: background 0.3s ease; 
    }

    #menuFab:hover { 
        background-color: #005ad1; 
    }

    details, 
    .table-container, 
    .recommendation-card { 
        overflow: visible !important; 
        position: relative; 
        z-index: 0; 
    }

    details ul { 
        margin-left: 1.5em; 
    }

    @media print { 
        #savePdfBtn, 
        #printContainer, 
        .table-pagination, 
        #menuFab, 
        .tabs-card { 
            display: none !important; 
        } 
        details { 
            display: block; 
        } 
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

    @media (max-width: 800px) { 
        .nav-drawer { 
            width: 240px; 
            left: -240px; 
        } 
        .nav-drawer.open { 
            left: 0; 
        } 
    }

    @media (max-width: 600px) { 
        .hero-metrics { 
            flex-direction: column; 
            align-items: center; 
        } 
        .metric-card { 
            width: 80%; 
        } 
    }
    @media (max-width: 600px) {
        .header .tabs {
            display: none;
        }
        #menuFab {
            display: flex; /* or block, as needed */
        }
    }

    @media (min-width: 601px) {
        .header .tabs {
            display: flex;
        }
        #menuFab {
            display: none;
        }
    }

    .tab-content { display: none;
      opacity: 0;
      transform: translateY(16px);
      transition: opacity 200ms ease, transform 200ms ease;
      pointer-events: none;
      position: absolute;
      width: 100%;
    }
    .tab-content.active { display: block;
      opacity: 1;
      transform: translateY(0);
      pointer-events: auto;
      position: relative;
    }

.progress-bar {
  background: #eee;
  border-radius: 10px;
  overflow: hidden;
  height: 20px;
  position: relative;
}

.progress {
  background-color: var(--score-color, #2196F3);
  height: 100%;
  position: relative;
  transition: width 1s ease-out;
}

.progress-text {
  position: absolute;
  right: 10px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 16px;
  font-weight: bold;
  color: #fff;
  z-index: 2;
}

.pulse-dot {
  position: absolute;
  right: 0;
  top: 50%;
  transform: translate(50%, -50%);
  width: 10px;
  height: 10px;
  background: white;
  border: 2px solid var(--score-color, #2196F3);
  border-radius: 50%;
  opacity: 0;
  transition: opacity 0.3s ease;
}

.pulse-dot.pulse {
  animation: pulse 1.5s infinite;
  opacity: 1;
}

@keyframes pulse {
  0% {
    transform: translate(50%, -50%) scale(1);
    opacity: 1;
  }
  70% {
    transform: translate(50%, -50%) scale(1.5);
    opacity: 0.3;
  }
  100% {
    transform: translate(50%, -50%) scale(1);
    opacity: 1;
  }
}

    .cluster-health {
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
        margin-bottom: 20px;
    }
    .health-score {
        flex: 1;
    }
    .pie-chart.donut {
      transform: rotate(-90deg);
    }
      .health-pie {
      display: flex;
      justify-content: center;
      align-items: center;
    }


.donut-ring {
  stroke: #ECEFF1; /* light grey background ring */
  fill: none;
}

.donut-segment {
  fill: none;
  stroke: $scoreColor;
  stroke-linecap: round;
  transition: stroke-dasharray 1s ease-out;
}

  @keyframes fillDonut {
    from {
      stroke-dasharray: 0, 100;
    }
    to {
      stroke-dasharray: var(--percent, 0), 100;
    }
  }

  .donut-segment {
    animation: fillDonut 1s ease-out forwards;
  }
    .centered-donut {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}


  @keyframes pulse {
  0%, 100% {
    r: 0.6;
    opacity: 1;
  }
  50% {
    r: 1.2;
    opacity: 0.6;
  }
}

#pulseDot {
  opacity: 0;
  transition: opacity 0.3s ease;
  pointer-events: none;
}
.pulse {
  animation: pulseAnim 1s ease-out infinite;
  opacity: 1;
}

@keyframes pulseAnim {
  0% { r: 2; opacity: 1; }
  50% { r: 3.5; opacity: 0.6; }
  100% { r: 2; opacity: 1; }
}


  </style>
</head>
<body>
  <div class="wrapper">
    <div class="main-content">
  <!-- Full-width header container -->
  <div class="header">
    <!-- Inner wrapper keeps content from going 100% edge-to-edge 
         but also remains centered and flexible up to max-width -->
    <div class="header-inner">

      <!-- Top row with cluster name and date on opposite ends -->
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

      <!-- Tabs row -->
      <ul class="tabs">
        <li class="tab active" data-tab="summary">Summary</li>
        <li class="tab" data-tab="nodes">Nodes</li>
        <li class="tab" data-tab="namespaces">Namespaces</li>
        <li class="tab" data-tab="workloads">Workloads</li>
        <li class="tab" data-tab="pods">Pods</li>
        <li class="tab" data-tab="jobs">Jobs</li>
        <li class="tab" data-tab="networking">Networking</li>
        <li class="tab" data-tab="storage">Storage</li>
        <li class="tab" data-tab="configuration">Configuration</li>
        <li class="tab" data-tab="security">Security</li>
        <li class="tab" data-tab="events">Kubernetes Events</li>
        <li class="tab" data-tab="allChecks">Custom Checks</li>
        $(if ($aks) { '<li class="tab" data-tab="aks">AKS Best Practices</li>' })
      </ul>
    </div>
  </div>

    <!-- Navigation Drawer -->
  <div id="navDrawer" class="nav-drawer">
    <div class="nav-header">
      <h3>Menu</h3>
      <button id="navClose" class="nav-close">&times;</button>
    </div>
    <ul class="nav-items"></ul>
  </div>
  <div id="navScrim" class="nav-scrim"></div>
  <button id="menuFab">☰</button>

  <!-- Tab Content Sections -->
<div class="tab-content active" id="summary">
  <div class="container">
    <h1 id="Health">Cluster Overview</h1>
    <div class="cluster-health">
      <div class="health-score">
      <h2>Cluster Health Score</h2>
        $scoreBarHtml
      </div>
      <div class="health-pie centered-donut">
        <h2>Passed / Failed Checks</h2>
        $pieChartHtml
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
      <h2>Resource Usage <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Cluster-wide CPU and memory usage.</span></span></h2>
      <div class="hero-metrics">
        <div class="metric-card $cpuClass">🖥 CPU: <strong>$cpuUsage%</strong><br><span>$cpuStatus</span></div>
        <div class="metric-card $memClass">💾 Memory: <strong>$memUsage%</strong><br><span>$memStatus</span></div>
      </div>
      <h2>Cluster Events <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Summary of recent warning and error events.</span></span></h2>
      <div class="hero-metrics">
        <div class="metric-card $errorClass">❌ Errors: <strong>$eventErrors</strong></div>
        <div class="metric-card $warningClass">⚠️ Warnings: <strong>$eventWarnings</strong></div>
      </div>
      $excludedNamespacesHtml
    </div>
  </div>
  
  <div class="tab-content" id="nodes">
    <div class="container">
      <h1>Node Conditions & Resources</h1>
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
  
  <div class="tab-content" id="customChecks">
    <div class="container">
      <h1>Custom Checks</h1>
      <div class="table-container">$collapsibleCustomChecksHtml</div>
    </div>
  </div>
  
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
