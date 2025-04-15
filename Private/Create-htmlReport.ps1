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
<h1 id="aks">AKS Best Practices Details</h1>
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
    @{ Id = "nodeConditions"; Cmd = { Show-NodeConditions -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "nodeResources"; Cmd = { Show-NodeResourceUsage -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "emptyNamespace"; Cmd = { Show-EmptyNamespaces -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "resourceQuotas"; Cmd = { Check-ResourceQuotas -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "namespaceLimitRanges"; Cmd = { Check-NamespaceLimitRanges -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "daemonSetIssues"; Cmd = { Show-DaemonSetIssues -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "HPA"; Cmd = { Check-HPAStatus -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "missingResourceLimits"; Cmd = { Check-MissingResourceLimits -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "PDB"; Cmd = { Check-PodDisruptionBudgets -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "missingProbes"; Cmd = { Check-MissingHealthProbes -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "podsRestart"; Cmd = { Show-PodsWithHighRestarts -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "podLongRunning"; Cmd = { Show-LongRunningPods -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "podFail"; Cmd = { Show-FailedPods -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "podPending"; Cmd = { Show-PendingPods -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "crashloop"; Cmd = { Show-CrashLoopBackOffPods -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "leftoverDebug"; Cmd = { Show-LeftoverDebugPods -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "stuckJobs"; Cmd = { Show-StuckJobs -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "jobFail"; Cmd = { Show-FailedJobs -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "servicesWithoutEndpoints"; Cmd = { Show-ServicesWithoutEndpoints -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "publicServices"; Cmd = { Check-PubliclyAccessibleServices -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "unmountedPV"; Cmd = { Show-UnusedPVCs -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "rbacMisconfig"; Cmd = { Check-RBACMisconfigurations -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "rbacOverexposure"; Cmd = { Check-RBACOverexposure -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "orphanedServiceAccounts"; Cmd = { Check-OrphanedServiceAccounts -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "orphanedRoles"; Cmd = { Check-OrphanedRoles -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "orphanedConfigMaps"; Cmd = { Check-OrphanedConfigMaps -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "orphanedSecrets"; Cmd = { Check-OrphanedSecrets -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "podsRoot"; Cmd = { Check-PodsRunningAsRoot -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "privilegedContainers"; Cmd = { Check-PrivilegedContainers -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "hostPidNet"; Cmd = { Check-HostPidAndNetwork -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "eventSummary"; Cmd = { Show-KubeEvents -Html -PageSize 999 -KubeData:$KubeData } },
    @{ Id = "deploymentIssues"; Cmd = { Check-DeploymentIssues -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "statefulSetIssues"; Cmd = { Check-StatefulSetIssues -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },
    @{ Id = "ingressHealth"; Cmd = { Check-IngressHealth -Html -PageSize 999 -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } },        
    # Add custom kubectl checks
    @{ Id = "customChecks"; Cmd = { Invoke-CustomKubectlChecks -Html -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData } }
  )

  $checkResults = @{}
  $customNavItems = @{}

  foreach ($check in $checks) {
    $html = & $check.Cmd
    if (-not $html) {
      $html = "<p>No data available for $($check.Id).</p>"
    }
    $checkResults[$check.Id] = $html
  
    # Handle custom checks
    if ($check.Id -eq "customChecks" -and $html -is [hashtable]) {
      $customChecksBySection = $html
      foreach ($section in $customChecksBySection.Keys) {
        $sanitizedId = $section -replace '[^\w]', ''
        $varName = "collapsible" + $sanitizedId + "Html"
        $sectionHtml = $customChecksBySection[$section]
  
        # Extract check IDs and Names from HTML
        $checkIds = [regex]::Matches($sectionHtml, "<h2 id='([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        $checkNames = [regex]::Matches($sectionHtml, "<h2 id='[^']+'>\s*[^-]+\s*-\s*([^<]+)\s*(?:<span.*?</span>)?\s*</h2>") |
        ForEach-Object { [string]$_.Groups[1].Value.Trim() }
  
        # Pair IDs with Names
        $checksInSection = for ($i = 0; $i -lt [Math]::Min($checkIds.Count, $checkNames.Count); $i++) {
          @{
            Id   = $checkIds[$i]
            Name = $checkNames[$i]
          }
        }
  
        # Map section to navigation category
        $navSection = if ($sectionToNavMap.ContainsKey($section)) { $sectionToNavMap[$section] } else { "Custom Checks" }
  
        # Store navigation items
        if (-not $customNavItems[$navSection]) {
          $customNavItems[$navSection] = @()
        }
        $customNavItems[$navSection] += $checksInSection
  
        # Store section HTML
        if (Get-Variable -Name $varName -Scope "Script" -ErrorAction SilentlyContinue) {
          Set-Variable -Name $varName -Value (@(
                  (Get-Variable -Name $varName -ValueOnly)
              $sectionHtml
            ) -join "`n")
        }
        else {
          Set-Variable -Name $varName -Value $sectionHtml
        }
      }
      continue
    }
  
    # Extract <p> summary if present
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
    $noFindings = $pre -match '✅'
    $recommendation = ""
  
    # Special handling for node conditions and resources
    if ($check.Id -in @("nodeConditions", "nodeResources")) {
      $warningsCount = 0
      if ($check.Id -eq "nodeConditions" -and $pre -match "Total Not Ready Nodes: (\d+)") {
        $warningsCount = [int]$matches[1]
      }
      elseif ($check.Id -eq "nodeResources" -and $pre -match "Total Resource Warnings Across All Nodes: (\d+)") {
        $warningsCount = [int]$matches[1]
      }
      $hasIssues = $warningsCount -ge 1
      $noFindings = $false  # Always show table for these
    }
  
  
    $defaultText = "Show Findings"
    $content = if ($noFindings) {
      "$pre`n"
    }
    else {
      "$pre`n" + (ConvertToCollapsible -Id $check.Id -defaultText $defaultText -content "$recommendation`n$html")
    }
  
    Set-Variable -Name ("collapsible" + $check.Id + "Html") -Value $content
  

    if ($check.Id -eq "eventSummary") {
      # Special handling for eventSummary, which returns two HTML fragments
      $summaryHtml = $html.SummaryHtml
      $eventsHtml = $html.EventsHtml

      # Process Warning Summary
      $summaryPre = if ($summaryHtml -match '^\s*<p>.*?</p>') {
        $matches[0]
      }
      else {
        "<p>⚠️ Warning Summary Report</p>"
      }
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
    <li><strong>Fix:</strong> Adjust resources (e.g., limits) or configs based on event type.</li>
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

      # Process Full Event Log
      $eventsPre = if ($eventsHtml -match '^\s*<p>.*?</p>') {
        $matches[0]
      }
      else {
        "<p>⚠️ Full Warning Event Log</p>"
      }
      $eventsContent = $eventsHtml -replace [regex]::Escape($eventsPre), ""
      $eventsHasIssues = $eventsContent -match '<tr>.*?<td>.*?</td>.*?</tr>' -and $eventsContent -notmatch 'No data available'
      $eventsNoFindings = $eventsPre -match '✅'
      $eventsRecommendation = if ($eventsHasIssues) {
        $recommendationText = @"
<div class="recommendation-content">
<h4>🛠️ Address Warning Events</h4>
<ul>
    <li><strong>Correlate:</strong> Match events to resources (<code>kubectl describe <resource> <name></code>).</li>
    <li><strong>Root Cause:</strong> Investigate logs or metrics for warnings.</li>
    <li><strong>Fix:</strong> Adjust resources (e.g., limits) or configs based on event type.</li>
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

      $eventsContentFinal = if ($eventsNoFindings) {
        "$eventsPre`n"
      }
      else {
        "$eventsPre`n" + (ConvertToCollapsible -Id "eventSummaryFullLog" -defaultText "Show Full Warning Event Log" -content "$eventsRecommendation`n$eventsContent")
      }
      Set-Variable -Name "collapsibleEventSummaryFullLogHtml" -Value $eventsContentFinal

      continue  # Skip the default processing for eventSummary
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
    $recommendation = ""

    $noFindings = $pre -match '✅'

    if ($check.Id -in @("nodeConditions", "nodeResources")) {
      $warningsCount = 0
      if ($check.Id -eq "nodeConditions" -and $pre -match "Total Not Ready Nodes: (\d+)") {
        $warningsCount = [int]$matches[1]
      }
      elseif ($check.Id -eq "nodeResources" -and $pre -match "Total Resource Warnings Across All Nodes: (\d+)") {
        $warningsCount = [int]$matches[1]
      }
      $hasIssues = $warningsCount -ge 1
      $noFindings = $warningsCount -eq 0
      # Override noFindings for nodeConditions and nodeResources to always show the table
      if ($check.Id -in @("nodeConditions", "nodeResources")) {
        $noFindings = $false
      }
    }

    if ($hasIssues) {
      $recommendationText = switch ($check.Id) {
        "nodeConditions" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix Node Issues</h4>
<ul>
    <li><strong>Check Node Status:</strong> Run <code>kubectl describe node <node-name></code> to inspect conditions like DiskPressure, MemoryPressure, or NotReady states.</li>
    <li><strong>Taints and Tolerations:</strong> If nodes are tainted, ensure pods have matching tolerations (<code>kubectl edit node <node-name></code> to remove unnecessary taints).</li>
    <li><strong>Resource Exhaustion:</strong> If nodes are overloaded, scale up the cluster (<code>az aks scale</code>) or evict pods to other nodes.</li>
    <li><strong>Logs:</strong> Check system logs via <code>kubectl logs -n kube-system</code> for kubelet or other issues.</li>
</ul>
</div>
"@
        }
        "nodeResources" {
          @"
<div class="recommendation-content">
<h4>🛠️ Optimize Resource Usage</h4>
<ul>
    <li><strong>Monitor Usage:</strong> Use <code>kubectl top nodes</code> to identify nodes with high CPU/memory usage (>80%).</li>
    <li><strong>Scale Nodes:</strong> Add more nodes if capacity is consistently exceeded (<code>az aks nodepool add</code> for AKS).</li>
    <li><strong>Pod Limits:</strong> Set resource requests/limits in pod specs to prevent overconsumption (e.g., <code>resources: { requests: { cpu: "100m" } }</code>).</li>
    <li><strong>Horizontal Scaling:</strong> Deploy a HorizontalPodAutoscaler (<code>kubectl autoscale</code>) for workloads causing spikes.</li>
    <li><strong>Eviction:</strong> Manually reschedule pods (<code>kubectl drain <node-name></code>) if a node is overloaded.</li>
</ul>
</div>
"@
        }
        "emptyNamespace" {
          @"
<div class="recommendation-content">
<h4>🛠️ Clean Up Empty Namespaces</h4>
<ul>
    <li><strong>Verify Usage:</strong> Check if namespaces are truly unused with <code>kubectl get all -n <namespace></code>.</li>
    <li><strong>Delete:</strong> Remove empty namespaces with <code>kubectl delete ns <namespace></code> to reduce clutter.</li>
    <li><strong>Documentation:</strong> If retained, document their purpose in a ConfigMap or team wiki to avoid confusion.</li>
    <li><strong>Automation:</strong> Consider a cronjob to periodically clean up unused namespaces.</li>
</ul>
</div>
"@
        }
        "resourceQuotas" {
          @"
<div class="recommendation-content">
<h4>🛠️ Set ResourceQuotas</h4>
<ul>
    <li><strong>Define:</strong> Create ResourceQuota objects with limits on CPU, memory, and pods per namespace.</li>
    <li><strong>Example:</strong> 
<pre><code>apiVersion: v1
kind: ResourceQuota
metadata:
name: compute-resources
spec:
hard:
  pods: "10"
  requests.cpu: "1"
  requests.memory: 1Gi
  limits.cpu: "2"
  limits.memory: 2Gi
</code></pre></li>
    <li><strong>Scope:</strong> Apply different quotas per environment (e.g., dev vs prod).</li>
    <li><strong>Monitor:</strong> Use <code>kubectl describe quota -n <namespace></code> to see usage.</li>
</ul>
</div>
"@
        }
        "namespaceLimitRanges" {
          @"
<div class="recommendation-content">
<h4>🛠️ Add LimitRanges</h4>
<ul>
    <li><strong>Define Defaults:</strong> Set default requests and limits per container using LimitRange.</li>
    <li><strong>Example:</strong> 
<pre><code>apiVersion: v1
kind: LimitRange
metadata:
name: limits
spec:
limits:
- default:
    cpu: "500m"
    memory: "512Mi"
  defaultRequest:
    cpu: "250m"
    memory: "256Mi"
  type: Container
</code></pre></li>
    <li><strong>Purpose:</strong> Prevent pods from running without resource caps or defaults.</li>
    <li><strong>Apply:</strong> <code>kubectl apply -f limitrange.yaml -n <namespace></code></li>
</ul>
</div>
"@
        }
        "daemonSetIssues" {
          @"
<div class="recommendation-content">
<h4>🛠️ Resolve DaemonSet Issues</h4>
<ul>
    <li><strong>Inspect Logs:</strong> Check pod logs with <code>kubectl logs -l <selector> -n <namespace></code> for errors.</li>
    <li><strong>Node Affinity:</strong> Ensure DaemonSet spec matches node conditions (<code>kubectl describe ds <name></code>).</li>
    <li><strong>Tolerations:</strong> Add tolerations if nodes are tainted (<code>spec.template.spec.tolerations</code>).</li>
    <li><strong>Rollout:</strong> Restart rollout if stuck (<code>kubectl rollout restart ds <name></code>).</li>
</ul>
</div>
"@
        }
        "deployments" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix Deployment Issues</h4>
<ul>
    <li><strong>Rollout Status:</strong> Use <code>kubectl rollout status deploy <name> -n <namespace></code> to check for rollout problems.</li>
    <li><strong>Unavailable Pods:</strong> If replicas are unavailable, inspect pod events and logs for failures.</li>
    <li><strong>Strategy:</strong> Consider using <code>RollingUpdate</code> with a proper <code>maxUnavailable</code> setting to avoid disruption.</li>
    <li><strong>Recreate:</strong> Use <code>kubectl rollout restart deploy <name></code> if stuck or hanging.</li>
</ul>
</div>
"@
        }
        "statefulsets" {
          @"
<div class="recommendation-content">
<h4>🛠️ Review StatefulSet Health</h4>
<ul>
    <li><strong>Pod Status:</strong> Check pod readiness and init status with <code>kubectl get pods -l app=<label> -n <namespace></code>.</li>
    <li><strong>Persistent Volumes:</strong> Verify PVCs are properly bound and mounted.</li>
    <li><strong>Pod Ordinality:</strong> StatefulSets start pods in order. A stuck pod blocks the rest—check logs of the first pod.</li>
    <li><strong>Headless Service:</strong> Ensure a headless service is defined for network identity.</li>
</ul>
</div>
"@
        }
        "HPA" {
          @"
<div class='recommendation-content'>
<h4>🛠️ Configure Horizontal Pod Autoscalers</h4>
<ul>
  <li><strong>Enable Scaling:</strong> Apply HPA to workloads using <code>kubectl autoscale deploy <name> --min=1 --max=5 --cpu-percent=80</code>.</li>
  <li><strong>CPU/Memory Metrics:</strong> Ensure the metrics server is deployed and working correctly.</li>
  <li><strong>Custom Metrics:</strong> Use <code>external.metrics.k8s.io</code> or <code>custom.metrics.k8s.io</code> for advanced autoscaling logic.</li>
  <li><strong>Validation:</strong> Monitor scaling events with <code>kubectl describe hpa <name></code>.</li>
</ul>
</div>
"@ 
        }
        "missingResourceLimits" {
          @"
<div class='recommendation-content'>
<h4>🛠️ Add Resource Requests and Limits</h4>
<ul>
  <li><strong>Define Requests:</strong> Use <code>resources.requests</code> for <code>cpu</code> and <code>memory</code> to guarantee minimum resources.</li>
  <li><strong>Define Limits:</strong> Use <code>resources.limits</code> to cap maximum usage for <code>cpu</code> and <code>memory</code>.</li>
  <li><strong>Example:</strong> 
    <pre><code>resources:
requests:
  cpu: "250m"
  memory: "128Mi"
limits:
  cpu: "500m"
  memory: "256Mi"</code></pre>
  </li>
  <li><strong>Why:</strong> Avoids resource contention, supports fair scheduling, and prevents overcommitment.</li>
  <li><strong>Policy Tips:</strong> Use <code>LimitRanges</code> and admission policies to apply defaults or enforce constraints.</li>
</ul>
</div>
"@
        }
        "PDB" {
          @"
<div class='recommendation-content'>
<h4>🛠️ Improve PDB Coverage</h4>
<ul>
  <li><strong>Apply PDBs:</strong> Create PDBs for all critical workloads to control voluntary disruptions.</li>
  <li><strong>Avoid Weak PDBs:</strong> Don't set <code>minAvailable: 0</code> or <code>maxUnavailable: 100%</code>—they offer no protection.</li>
  <li><strong>Label Matching:</strong> Verify selectors actually match pods (<code>spec.selector.matchLabels</code>).</li>
  <li><strong>Dry Run:</strong> Use <code>kubectl get pdb -o wide</code> to confirm expected pod count.</li>
</ul>
</div>
"@ 
        }
        "missingProbes" {
          @"
<div class='recommendation-content'>
<h4>🛠️ Add Health Probes</h4>
<ul>
  <li><strong>Readiness Probes:</strong> Signal when the container is ready to serve traffic.</li>
  <li><strong>Liveness Probes:</strong> Detect deadlocked or crashed apps. Example: <code>httpGet</code> or <code>exec</code>.</li>
  <li><strong>Startup Probes:</strong> Useful for slow-starting apps to avoid premature kills.</li>
  <li><strong>Validation:</strong> Test probe behavior with <code>kubectl describe pod <name></code>.</li>
</ul>
</div>
"@ 
        }
        "podsRestart" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix High Restart Pods</h4>
<ul>
    <li><strong>Logs:</strong> Review pod logs (<code>kubectl logs <pod-name> -n <namespace></code>) to identify crash reasons.</li>
    <li><strong>Resources:</strong> Increase CPU/memory limits in pod spec if resource starvation is suspected.</li>
    <li><strong>Liveness Probes:</strong> Adjust or remove overly strict liveness probes causing restarts (<code>spec.containers.livenessProbe</code>).</li>
    <li><strong>App Debugging:</strong> Fix application code if it’s exiting unexpectedly (check exit codes).</li>
</ul>
</div>
"@
        }
        "podLongRunning" {
          @"
<div class="recommendation-content">
<h4>🛠️ Handle Long-Running Pods</h4>
<ul>
    <li><strong>Verify Intent:</strong> Confirm if pods should run indefinitely (<code>kubectl describe pod <pod-name></code>).</li>
    <li><strong>Stuck Jobs:</strong> If from a Job, check job status (<code>kubectl describe job <job-name></code>) and delete if stuck (<code>kubectl delete pod <pod-name></code>).</li>
    <li><strong>Timeouts:</strong> Add pod disruption budgets or termination grace periods to manage lifecycle.</li>
    <li><strong>Monitoring:</strong> Set up alerts for pods exceeding expected runtime.</li>
</ul>
</div>
"@
        }
        "podFail" {
          @"
<div class="recommendation-content">
<h4>🛠️ Resolve Failed Pods</h4>
<ul>
    <li><strong>Events:</strong> Check events with <code>kubectl describe pod <pod-name> -n <namespace></code> for failure reasons.</li>
    <li><strong>Logs:</strong> Inspect logs (<code>kubectl logs <pod-name> --previous</code>) for crash details.</li>
    <li><strong>Exit Codes:</strong> Decode exit codes (e.g., 1 for app error, 137 for OOM) and adjust app or resources.</li>
    <li><strong>Restart Policy:</strong> Ensure pod spec’s restartPolicy is appropriate (<code>Never</code> vs <code>OnFailure</code>).</li>
</ul>
</div>
"@
        }
        "podPending" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix Pending Pods</h4>
<ul>
    <li><strong>Resources:</strong> Check cluster capacity (<code>kubectl top nodes</code>) and quotas (<code>kubectl get resourcequota -n <namespace></code>).</li>
    <li><strong>Taints:</strong> Add tolerations if nodes are tainted (<code>kubectl edit pod <pod-name></code>).</li>
    <li><strong>Scheduling:</strong> Review node affinity/selectors (<code>kubectl describe pod <pod-name></code>).</li>
    <li><strong>Scale:</strong> Add nodes if cluster is at capacity (<code>az aks scale</code>).</li>
</ul>
</div>
"@
        }
        "crashloop" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix CrashLoopBackOff Pods</h4>
<ul>
    <li><strong>Logs:</strong> Check logs (<code>kubectl logs <pod-name> -n <namespace></code>) for crash causes.</li>
    <li><strong>Resources:</strong> Increase requests/limits if OOMKilled (<code>spec.containers.resources</code>).</li>
    <li><strong>Probes:</strong> Adjust readiness/liveness probes if too aggressive (<code>spec.containers.livenessProbe</code>).</li>
    <li><strong>App Fix:</strong> Debug app code for unhandled exceptions or misconfiguration.</li>
</ul>
</div>
"@
        }
        "leftoverDebug" {
          @"
<div class="recommendation-content">
<h4>🛠️ Remove Debug Pods</h4>
<ul>
    <li><strong>Identify:</strong> Confirm pods are debug-related (<code>kubectl describe pod <pod-name></code>).</li>
    <li><strong>Delete:</strong> Remove with <code>kubectl delete pod <pod-name> -n <namespace></code>).</li>
    <li><strong>Policy:</strong> Set TTL or cleanup scripts to auto-remove debug pods post-use.</li>
    <li><strong>Monitoring:</strong> Alert on lingering debug pods to prevent resource waste.</li>
</ul>
</div>
"@
        }
        "stuckJobs" {
          @"
<div class="recommendation-content">
<h4>🛠️ Resolve Stuck Jobs</h4>
<ul>
    <li><strong>Status:</strong> Inspect job with <code>kubectl describe job <job-name></code> for pod failures.</li>
    <li><strong>Pods:</strong> Check pod logs (<code>kubectl logs -l job-name=<job-name></code>) for errors.</li>
    <li><strong>Delete:</strong> Remove stuck jobs (<code>kubectl delete job <job-name></code>) if unresolvable.</li>
    <li><strong>Backoff:</strong> Adjust <code>spec.backoffLimit</code> if retries are exhausted too quickly.</li>
</ul>
</div>
"@
        }
        "jobFail" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix Failed Jobs</h4>
<ul>
    <li><strong>Logs:</strong> Review pod logs (<code>kubectl logs -l job-name=<job-name></code>) for failure details.</li>
    <li><strong>Spec:</strong> Check job spec (<code>kubectl get job <job-name> -o yaml</code>) for misconfiguration.</li>
    <li><strong>Resources:</strong> Ensure sufficient CPU/memory (<code>spec.template.spec.resources</code>).</li>
    <li><strong>Retry:</strong> Increase <code>spec.backoffLimit</code> or fix underlying app issues.</li>
</ul>
</div>
"@
        }
        "servicesWithoutEndpoints" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix Services Without Endpoints</h4>
<ul>
    <li><strong>Selectors:</strong> Verify service selectors match pod labels (<code>kubectl describe svc <svc-name></code>).</li>
    <li><strong>Pods:</strong> Deploy missing pods or fix pod failures (<code>kubectl get pods -l <selector></code>).</li>
    <li><strong>Network:</strong> Ensure network policies aren’t blocking endpoints.</li>
    <li><strong>Debug:</strong> Use <code>kubectl get endpoints <svc-name></code> to confirm endpoint creation.</li>
</ul>
</div>
"@
        }
        "publicServices" {
          @"
<div class="recommendation-content">
<h4>🛠️ Secure Public Services</h4>
<ul>
    <li><strong>Check Exposure:</strong> List services with <code>kubectl get svc -A | grep LoadBalancer</code>.</li>
    <li><strong>Restrict:</strong> Apply network policies to limit access (<code>kubectl apply -f policy.yaml</code>).</li>
    <li><strong>Internal:</strong> Use <code>service.beta.kubernetes.io/azure-load-balancer-internal: "true"</code> for AKS.</li>
    <li><strong>Review:</strong> Audit if public access is intentional or reduce scope.</li>
</ul>
</div>
"@
        }
        "ingress" {
          @"
<div class="recommendation-content">
<h4>🛠️ Validate Ingress Resources</h4>
<ul>
    <li><strong>Backend Services:</strong> Verify Ingress routes to services with healthy endpoints.</li>
    <li><strong>Annotations:</strong> Confirm correct ingress class or controller annotations.</li>
    <li><strong>TLS:</strong> Use <code>cert-manager</code> or secrets to configure valid TLS certs.</li>
    <li><strong>Check Errors:</strong> Look for HTTP 404s, 502s or connection errors in the ingress controller logs.</li>
</ul>
</div>
"@
        }
        "unmountedPV" {
          @"
<div class="recommendation-content">
<h4>🛠️ Handle Unmounted PVs</h4>
<ul>
    <li><strong>Verify:</strong> Check PVC status (<code>kubectl get pvc -A</code>) and pod mounts.</li>
    <li><strong>Reclaim:</strong> Delete unused PVCs (<code>kubectl delete pvc <pvc-name> -n <namespace></code>).</li>
    <li><strong>Reattach:</strong> Mount to a pod if needed (<code>spec.volumes</code> in pod spec).</li>
    <li><strong>Cleanup:</strong> Set reclaim policy to <code>Delete</code> if no longer needed (<code>kubectl edit pv</code>).</li>
</ul>
</div>
"@
        }
        "rbacMisconfig" {
          @"
<div class="recommendation-content">
<h4>🛠️ Fix RBAC Misconfigurations</h4>
<ul>
    <li><strong>Audit:</strong> List bindings (<code>kubectl get clusterrolebinding,rolebinding -A</code>).</li>
    <li><strong>Subjects:</strong> Add missing subjects (<code>kubectl edit clusterrolebinding <name></code>).</li>
    <li><strong>Remove:</strong> Delete unused roles/bindings (<code>kubectl delete clusterrole <name></code>).</li>
    <li><strong>Test:</strong> Use <code>kubectl auth can-i</code> to verify permissions.</li>
</ul>
</div>
"@
        }
        "rbacOverexposure" {
          @"
<div class="recommendation-content">
<h4>🛠️ Reduce RBAC Overexposure</h4>
<ul>
    <li><strong>Audit:</strong> Check permissions (<code>kubectl auth can-i --list -A</code>).</li>
    <li><strong>Scope:</strong> Replace cluster-wide roles with namespace-specific ones (<code>kubectl create role</code>).</li>
    <li><strong>Least Privilege:</strong> Limit verbs/resources in role definitions.</li>
    <li><strong>Review:</strong> Regularly audit with tools like <code>rbac-tool</code> or <code>kubectl who-can</code>.</li>
</ul>
</div>
"@
        }
        "orphanedConfigMaps" {
          @"
<div class="recommendation-content">
<h4>🛠️ Clean Up Orphaned ConfigMaps</h4>
<ul>
    <li><strong>Verify:</strong> Check usage (<code>kubectl describe cm <name> -n <namespace></code>).</li>
    <li><strong>Delete:</strong> Remove unused ConfigMaps (<code>kubectl delete cm <name> -n <namespace></code>).</li>
    <li><strong>Documentation:</strong> Note purpose in annotations if retained.</li>
    <li><strong>Automation:</strong> Script cleanup for unused ConfigMaps.</li>
</ul>
</div>
"@
        }
        "orphanedSecrets" {
          @"
<div class="recommendation-content">
<h4>🛠️ Handle Orphaned Secrets</h4>
<ul>
    <li><strong>Check:</strong> Verify usage (<code>kubectl describe secret <name> -n <namespace></code>).</li>
    <li><strong>Delete:</strong> Remove unused Secrets (<code>kubectl delete secret <name> -n <namespace></code>).</li>
    <li><strong>Mount:</strong> Ensure Secrets are mounted or referenced if needed (<code>spec.volumes.secret</code>).</li>
    <li><strong>Security:</strong> Rotate if exposed and no longer used.</li>
</ul>
</div>
"@
        }
        "podsRoot" {
          @"
<div class="recommendation-content">
<h4>🛠️ Secure Root Pods</h4>
<ul>
    <li><strong>Config:</strong> Set <code>securityContext.runAsNonRoot: true</code> in pod spec.</li>
    <li><strong>User:</strong> Define <code>runAsUser: <non-zero-uid></code> to avoid root.</li>
    <li><strong>Verify:</strong> Check with <code>kubectl exec <pod-name> -- whoami</code>.</li>
    <li><strong>Policy:</strong> Enforce via PodSecurity admission controller.</li>
</ul>
</div>
"@
        }
        "privilegedContainers" {
          @"
<div class="recommendation-content">
<h4>🛠️ Remove Privileged Containers</h4>
<ul>
    <li><strong>Check:</strong> Inspect spec (<code>kubectl get pod <pod-name> -o yaml</code>).</li>
    <li><strong>Fix:</strong> Remove <code>privileged: true</code> from <code>securityContext</code>.</li>
    <li><strong>Capabilities:</strong> Use specific capabilities instead (<code>securityContext.capabilities.add</code>).</li>
    <li><strong>Audit:</strong> Block privileged pods with Open Policy Agent or PodSecurity admission controller.</li>
</ul>
</div>
"@
        }
        "hostPidNet" {
          @"
<div class="recommendation-content">
<h4>🛠️ Disable Host PID/Network</h4>
<ul>
    <li><strong>Inspect:</strong> Check pod spec (<code>kubectl get pod <pod-name> -o yaml</code>).</li>
    <li><strong>Fix:</strong> Set <code>hostPID: false</code> and <code>hostNetwork: false</code> in <code>spec</code>.</li>
    <li><strong>Use Case:</strong> Justify if required (e.g., monitoring tools), otherwise remove.</li>
    <li><strong>Security:</strong> Enforce via admission controllers to prevent host access.</li>
</ul>
</div>
"@
        }
        "orphanedServiceAccounts" {
          @"
<div class="recommendation-content">
<h4>🛠️ Clean Up Orphaned ServiceAccounts</h4>
<ul>
    <li><strong>Verify:</strong> Run <code>kubectl get sa -A</code> and check usage across pods, RoleBindings, and ClusterRoleBindings.</li>
    <li><strong>Delete:</strong> Remove unused SAs with <code>kubectl delete sa <name> -n <namespace></code>.</li>
    <li><strong>Audit:</strong> Confirm bindings and pods no longer reference the SA to avoid runtime issues.</li>
    <li><strong>Policy:</strong> Set up a process to review and clean up stale SAs periodically.</li>
</ul>
</div>
"@
        }
        "orphanedRoles" {
          @"
<div class="recommendation-content">
<h4>🛠️ Remove Unused Roles and ClusterRoles</h4>
<ul>
    <li><strong>List:</strong> Get all Roles and ClusterRoles using <code>kubectl get roles,clusterroles -A</code>.</li>
    <li><strong>Bindings:</strong> Confirm if they’re bound using <code>kubectl get rolebindings,clusterrolebindings -A</code>.</li>
    <li><strong>Prune:</strong> Delete unused roles with <code>kubectl delete role <name> -n <namespace></code> or <code>kubectl delete clusterrole <name></code>.</li>
    <li><strong>Review:</strong> Avoid clutter and reduce audit noise by cleaning up unbound roles regularly.</li>
</ul>
</div>
"@
        }
        "eventSummary" {
          @"
<div class="recommendation-content">
<h4>🛠️ Address Cluster Events</h4>
<ul>
    <li><strong>Correlate:</strong> Match events to resources (<code>kubectl describe <resource> <name></code>).</li>
    <li><strong>Root Cause:</strong> Investigate logs or metrics for warnings/errors.</li>
    <li><strong>Fix:</strong> Adjust resources (e.g., limits) or configs based on event type.</li>
    <li><strong>Monitor:</strong> Set up alerts for recurring critical events.</li>
</ul>
</div>
"@
        }
        default {
          @"
<div class="recommendation-content">
<h4>🛠️ Generic Fix</h4>
<ul>
    <li><strong>Inspect:</strong> Use <code>kubectl describe</code> on affected resources.</li>
    <li><strong>Logs:</strong> Check logs for clues (<code>kubectl logs</code>).</li>
    <li><strong>Config:</strong> Review and adjust YAML manifests.</li>
    <li><strong>Docs:</strong> Refer to Kubernetes documentation for specific guidance.</li>
</ul>
</div>
"@
        }
      }
      $recommendation = @"
<div class="recommendation-card">
<details style='margin-bottom: 10px;'>
    <summary style='color: #0071FF; font-weight: bold; font-size: 14px; padding: 10px; background: #E3F2FD; border-radius: 4px 4px 0 0;'>Recommendations</summary>
    $recommendationText
</details>
</div>
<div style='height: 15px;'></div>
"@
    }

    $defaultText = if ($check.Id -eq "eventSummary") { "Show Event Findings" } else { "Show Findings" }
    $content = if ($noFindings) {
      "$pre`n"
    }
    else {
      "$pre`n" + (ConvertToCollapsible -Id $check.Id -defaultText $defaultText -content "$recommendation`n$html")
    }

    Set-Variable -Name ("collapsible" + $check.Id + "Html") -Value $content
  }

  $clusterSummaryText = $clusterSummaryRaw -join "`n"
  function Extract-Metric($label, $data) {
    if ($data -match "$label\s*:\s*([\d]+)") { [int]$matches[1] } else { "0" }
  }
  $clusterName = "Unknown"
  $k8sVersion = "Unknown"
  $clusterScore = Get-ClusterHealthScore -Checks $checkResults
  $scoreColor = if ($clusterScore -ge 80) {
    "#4CAF50"  # Green
  }
  elseif ($clusterScore -ge 50) {
    "#FF9800"  # Orange
  }
  else {
    "#F44336"  # Red
  }
  $scoreHeader = "<h2 style='margin-top: 0;'>Cluster: $ClusterName   |   Health Score: $clusterScore / 100</h2>"
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

  $htmlTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Kubernetes Cluster Report</title>
  <link rel="icon" href="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/assets/images/favicon.ico" type="image/x-icon">
  <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;700&display=swap');
  html { scroll-behavior: smooth; }
  body { font-family: 'Roboto', sans-serif; margin: 0; padding: 0; background: #eceff1; color: #37474f; }
  .header { background: linear-gradient(90deg, #005ad1, #0071FF); color: white; display: flex; justify-content: space-between; align-items: center; padding: 10px 24px; font-weight: bold; font-size: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.2); position: relative; top: auto; z-index: auto; }
  .header .nav-toggle { cursor: pointer; font-size: 28px; color: #fff; }
  .header .logo { height: 44px; margin-right: 12px; }
  .container { max-width: 1350px; margin: 20px auto; background: white; padding: 20px; border-radius: 12px; box-shadow: 0 6px 15px rgba(0, 0, 0, 0.1); }
  .compatibility { padding: 12px; border-radius: 8px; font-weight: bold; text-align: center; color: #ffffff; box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2); }
  .warning { background: #ffeb3b; } .healthy { background: #4CAF50; } .unknown { background: #9E9E9E; }
  .table-container { overflow-x: auto; width: 100%; max-width: 100%; }
  table { width: 100%; border-collapse: separate; border-spacing: 0; margin: 20px 0; font-size: 14px; text-align: left; background: #fff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-left: 1px solid #e0e0e0; border-right: 1px solid #e0e0e0; }
  th {
      background-color: #0071FF;
      color: white;
      padding: 12px;
      font-weight: 500;
      position: relative;
      cursor: pointer;
      white-space: nowrap; /* Prevent text wrapping */
      overflow: hidden; /* Hide overflow text */
      text-overflow: ellipsis; /* Add ellipsis for overflow text */
  }
  th:hover {
      background-color: #005ad1; /* Darker blue on hover */
  }
  th::after {
      content: '';
      display: inline-block;
      margin-left: 5px;
      vertical-align: middle;
  }
  td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f5f5f5; transition: background 0.2s; }
  th:first-child { border-top-left-radius: 8px; }
  th:last-child { border-top-right-radius: 8px; }
  td:first-child { border-left: none; }
  td:last-child { border-right: none; }
  table a {
      color: #0071FF;
      text-decoration: none;
      font-weight: 500;
  }
  table a:hover {
      text-decoration: underline;
      color: #005ad1;
  }
  #backToTop { position: fixed; bottom: 20px; right: 20px; background: #0071FF; color: #fff; padding: 10px 15px; border-radius: 25px; text-decoration: none; font-size: 14px; font-weight: bold; box-shadow: 0 4px 12px rgba(0,0,0,0.3); display: none; transition: opacity 0.3s ease; }
  #backToTop:hover { background: #005ad1; }
  #printContainer { text-align: right; margin-bottom: 15px; }
  #printContainer button { background: #0071FF; color: white; padding: 10px 15px; border: none; cursor: pointer; font-size: 16px; border-radius: 8px; transition: background 0.3s; }
  #printContainer button:hover { background: #005ad1; }
  #savePdfBtn { background: #0071FF; color: white; padding: 8px 12px; font-size: 14px; font-weight: bold; border: none; cursor: pointer; border-radius: 8px; margin-top: 10px; transition: background 0.3s; }
  #savePdfBtn:hover { background: #005ad1; }
@media print {
    #savePdfBtn, #printContainer, .table-pagination, #menuFab {
        display: none !important; /* Add !important to override any inline styles */
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
  .excluded-ns { padding: 2px 6px; background-color: #eee; border-radius: 4px; margin-right: 4px; display: inline-block; }
  .nav-drawer { position: fixed; top: 0; left: -280px; width: 280px; height: 100%; background: linear-gradient(135deg, #f5f7fa, #ffffff); box-shadow: 4px 0 12px rgba(0,0,0,0.2); transition: left 0.3s ease-in-out; z-index: 2000; overflow-y: auto; }
  .nav-drawer.open { left: 0; }
  .nav-scrim { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.4); z-index: 1999; display: none; }
  .nav-scrim.open { display: block; }
  .nav-content { padding: 20px; }
  .nav-header { padding: 20px; border-bottom: 1px solid #e0e0e0; display: flex; justify-content: space-between; align-items: center; background: #0071FF; color: #fff; }
  .nav-header h3 { margin: 0; font-size: 24px; font-weight: 700; }
  .nav-close { background: none; border: none; cursor: pointer; font-size: 28px; color: #fff; transition: color 0.3s; }
  .nav-close:hover { color: #BBDEFB; }
  .nav-items { list-style: none; padding: 0; margin: 0; }
  .nav-item { position: relative; }
  .nav-item a { display: flex; align-items: center; padding: 12px 20px; color: #37474f; text-decoration: none; font-size: 16px; font-weight: 400; transition: background-color 0.3s, color 0.3s; border-radius: 6px; }
  .nav-item a:hover { background: #E3F2FD; color: #005ad1; }
  .nav-item .material-icons { margin-right: 16px; font-size: 22px; color: #0071FF; }
  .nav-item details { margin: 5px 0; }
  .nav-item details summary { display: flex; align-items: center; padding: 12px 20px; color: #37474f; font-size: 16px; font-weight: 500; cursor: pointer; transition: background-color 0.3s, color 0.3s; border-radius: 6px; }
  .nav-item details summary:hover { background: #E3F2FD; color: #005ad1; }
  .nav-item details summary .material-icons { margin-right: 16px; font-size: 22px; color: #0071FF; }
  .nav-item details ul { padding-left: 48px; list-style: none; }
  .nav-item details ul li a { padding: 8px 20px; font-size: 14px; font-weight: 400; color: #455A64; border-radius: 6px; }
  .nav-item details ul li a:hover { background: #f0f4f8; color: #0071FF; }
  .summary-arrow {
      margin-left: auto;
      transition: transform 0.3s ease;
    }

    details[open] .summary-arrow {
      transform: rotate(180deg);
    }

  .ripple { position: absolute; border-radius: 50%; background: rgba(0,113,255,0.3); transform: scale(0); animation: ripple 0.6s linear; pointer-events: none; }
  @keyframes ripple { to { transform: scale(4); opacity: 0; } }
  @media (max-width: 800px) {
      .nav-drawer { width: 240px; left: -240px; }
      .nav-drawer.open { left: 0; }
  }
      details,
  .table-container,
  .recommendation-card {
    overflow: visible !important;
    position: relative;
    z-index: 0;
  }
  details ul { margin-left: 1.5em; }
  .hero-metrics { display: flex; justify-content: space-around; margin-bottom: 20px; flex-wrap: wrap; }
  .metric-card { text-align: center; padding: 20px; border-radius: 10px; color: white; font-size: 20px; font-weight: bold; min-width: 150px; flex: 1; margin: 10px; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1); }
  .normal { background-color: #388e3c; } .warning { background-color: #ffa000; } .critical { background-color: #B71C1C; } .default { background-color: #0071FF; }
  @media (max-width: 600px) { .hero-metrics { flex-direction: column; align-items: center; } .metric-card { width: 80%; } }
  .tooltip { display: inline-block; position: relative; cursor: pointer; margin-left: 8px; color: #0071FF; font-weight: bold; }
  .tooltip .tooltip-text { visibility: hidden; width: 260px; background-color: #0071FF; color: #fff; text-align: left; border-radius: 6px; padding: 8px; position: absolute; z-index: 10; bottom: 125%; left: 50%; margin-left: -130px; opacity: 0; transition: opacity 0.3s; font-size: 13px; }
  .tooltip:hover .tooltip-text { visibility: visible; opacity: 1; }
  .tooltip .tooltip-text::after { content: ""; position: absolute; top: 100%; left: 50%; margin-left: -6px; border-width: 6px; border-style: solid; border-color: #0071FF transparent transparent transparent; }
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
  .footer { background: linear-gradient(90deg, #263238, #37474f); color: white; text-align: center; padding: 20px; font-size: 14px; position: relative; }
  .footer a { color: #80cbc4; text-decoration: none; }
  .footer a:hover { text-decoration: underline; }
  .footer .logo { height: 30px; margin-bottom: 10px; }
  .recommendation-card { margin-bottom: 10px; }
  .recommendation-card details { background: #fff; border-radius: 8px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); }
  .recommendation-card summary { padding: 12px; background: #E3F2FD; border-radius: 8px 8px 0 0; }
  .recommendation-card summary:hover { background: #BBDEFB; }
  .recommendation-content { padding: 15px; background: #f9f9f9; border: 1px solid #BBDEFB; border-top: none; border-radius: 0 0 8px 8px; color: #37474f; line-height: 1.6; }
  .recommendation-content h4 { margin: 0 0 10px 0; font-size: 16px; color: #0071FF; }
  .recommendation-content ul { padding-left: 20px; margin: 0; }
  .recommendation-content li { margin-bottom: 10px; }
  .recommendation-content code { background: #e0e0e0; padding: 2px 4px; border-radius: 4px; font-family: 'Courier New', Courier, monospace; }
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
</style>
</head>
<body>
<div class="nav-drawer" id="navDrawer">
  <div class="nav-header">
      <h3>Navigation</h3>
      <button class="nav-close" id="navClose">✖</button>
  </div>
  <div class="nav-content">
      <ul class="nav-items">
          <li class="nav-item"><a href="#summary"><span class="material-icons">dashboard</span> Cluster Summary</a></li>
          <li class="nav-item">
              <details>
                  <summary><span class="material-icons">computer</span> Nodes</summary>
                  <ul>
                      <li><a href="#nodecon">Node Conditions</a></li>
                      <li><a href="#noderesource">Node Resources</a></li>
                  </ul>
              </details>
          </li>
          <li class="nav-item">
            <details>
              <summary><span class="material-icons">folder</span> Namespaces</summary>
              <ul>
                <li><a href="#namespaces">Empty Namespaces</a></li>
                <li><a href="#resourceQuotas">ResourceQuotas</a></li>
                <li><a href="#namespaceLimitRanges">LimitRanges</a></li>
              </ul>
            </details>
          </li>
          <li class="nav-item">
            <details>
              <summary><span class="material-icons">build</span> Workloads</summary>
              <ul>
                <li><a href="#daemonsets">DaemonSets</a></li>
                <li><a href="#deploymentIssues">Deployment Issues</a></li>
                <li><a href="#statefulSetIssues">StatefulSet Issues</a></li>
                <li><a href="#HPA">Horizontal Pod Autoscalers</a></li>
                <li><a href="#missingResourceLimits">Missing Resource Limits</a></li>
                <li><a href="#PDB">PodDisruptionBudgets</a></li>
                <li><a href="#missingProbes">Missing Health Probes</a></li>
              </ul>
            </details>
          </li>
          <li class="nav-item">
              <details>
                  <summary><span class="material-icons">hexagon</span> Pods</summary>
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
          <li class="nav-item">
              <details>
                  <summary><span class="material-icons">work</span> Jobs</summary>
                  <ul>
                      <li><a href="#stuckjobs">Stuck Jobs</a></li>
                      <li><a href="#failedjobs">Job Failures</a></li>
                  </ul>
              </details>
          </li>
          <li class="nav-item">
              <details>
                  <summary><span class="material-icons">network_check</span> Networking</summary>
                  <ul>
                      <li><a href="#servicenoendpoints">Services without Endpoints</a></li>
                      <li><a href="#publicServices">Public Services</a></li>
                      <li><a href="#ingressHealth">Ingress Health</a></li>
                  </ul>
              </details>
          </li>
          <li class="nav-item">
              <details>
                  <summary><span class="material-icons">storage</span> Storage</summary>
                  <ul>
                      <li><a href="#unmountedpv">Unmounted Persistent Volumes</a></li>
                  </ul>
              </details>
          </li>
          <li class="nav-item"><a href="#configuration"><span class="material-icons">settings</span> Configuration Hygiene</a></li>
          <li class="nav-item">
            <details>
              <summary><span class="material-icons">security</span> Security</summary>
              <ul>
                <!-- RBAC -->
                <li><a href="#rbacmisconfig">RBAC Misconfigurations</a></li>
                <li><a href="#rbacOverexposure">RBAC Overexposure</a></li>
                <li><a href="#orphanedRoles">Unused Roles</a></li>
                <li><a href="#orphanedServiceAccounts">Orphaned ServiceAccounts</a></li>
          
                <!-- Orphaned resources -->
                <li><a href="#orphanedconfigmaps">Orphaned ConfigMaps</a></li>
                <li><a href="#orphanedsecrets">Orphaned Secrets</a></li>
          
                <!-- Pod/container security -->
                <li><a href="#podsRoot">Pods Running as Root</a></li>
                <li><a href="#privilegedContainers">Privileged Containers</a></li>
                <li><a href="#hostPidNet">hostPID / hostNetwork</a></li>
              </ul>
            </details>
          </li>
          <li class="nav-item">
    <details>
        <summary><span class="material-icons">warning</span> Kubernetes Events</summary>
        <ul>
            <li><a href="#clusterwarnings">Warning Summary</a></li>
            <li><a href="#fulleventlog">Full Warning Event Log</a></li>
        </ul>
    </details>
</li>
$aksMenuItem
      </ul>
  </div>
</div>
<div class="nav-scrim" id="navScrim"></div>
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
  <div style="text-align: right; font-size: 13px; line-height: 1.4;">
      <div>Generated on: <strong>$today</strong></div>

      <div>Created by <a href="https://kubedeck.io" target="_blank" style="color: #ffffff; text-decoration: underline;">🌐 KubeDeck.io</a></div>
      <div style="margin-top: 4px;" id="printContainer"><button id="savePdfBtn">📄 Save as PDF</button></div>
  </div>
</div>
<div class="container">
  <h1 style="margin-top: 0;">Cluster Health Score</h1>
  <div style="margin: 20px 0;">
    <div style="font-size: 18px; margin-bottom: 6px;">
      Score: <strong>$clusterScore / 100</strong>
    </div>
    <div style="background-color: #e0e0e0; border-radius: 8px; height: 26px; width: 100%;">
      <div style="height: 100%; width: $clusterScore%; background-color: $scoreColor; border-radius: 8px; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold;">
        $clusterScore%
      </div>
    </div>
    <p style="margin-top: 10px; font-size: 16px; color: #555;">
      This score is calculated from key checks across nodes, workloads, security, and configuration best practices.
      <br>
      A higher score means fewer issues and better adherence to Kubernetes standards.
    </p>
  </div>
</div>
<div class="container">
  <h1 id="summary">Cluster Summary</h1>
  <p><strong>Cluster Name:</strong> $clusterName</p>
  <p><strong>Kubernetes Version:</strong> $k8sVersion</p>
  <div class="compatibility $compatibilityClass"><strong>$compatibilityCheck</strong></div>
  <h2>Cluster Metrics Summary <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Summary of node and pod counts including warnings, restarts, and issues.</span></span></h2>
  <table>
      <tr><td>🚀 Nodes: $totalNodes</td><td>🟩 Healthy: $healthyNodes</td><td>🟥 Issues: $issueNodes</td></tr>
      <tr><td>📦 Pods: $totalPods</td><td>🟩 Running: $runningPods</td><td>🟥 Failed: $failedPods</td></tr>
      <tr><td>🔄 Restarts: $totalRestarts</td><td>🟨 Warnings: $warnings</td><td>🟥 Critical: $critical</td></tr>
      <tr><td>⏳ Pending Pods: $pendingPods</td><td>🟡 Waiting: $pendingPods</td><td></td></tr>
      <tr><td>⚠️ Stuck Pods: $stuckPods</td><td>❌ Stuck: $stuckPods</td><td></td></tr>
      <tr><td>📉 Job Failures: $jobFailures</td><td>🔴 Failed: $jobFailures</td><td></td></tr>
  </table>
  <h2>Pod Distribution <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Average, min, and max pods per node, and total node count.</span></span></h2>
  <table><tr><td>Avg: <strong>$podAvg</strong></td><td>Max: <strong>$podMax</strong></td><td>Min: <strong>$podMin</strong></td><td>Total Nodes: <strong>$podTotalNodes</strong></td></tr></table>
  <h2>Resource Usage <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Cluster-wide CPU and memory usage.</span></span></h2>
  <div class="hero-metrics">
      <div class="metric-card $cpuClass">🖥 CPU: <strong>$cpuUsage%</strong> <br><span>$cpuStatus</span></div>
      <div class="metric-card $memClass">💾 Memory: <strong>$memUsage%</strong> <br><span>$memStatus</span></div>
  </div>
  <h2>Cluster Events <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Recent warning and error events from the cluster.</span></span></h2>
  <div class="hero-metrics">
      <div class="metric-card $errorClass">❌ Errors: <strong>$eventErrors</strong></div>
      <div class="metric-card $warningClass">⚠️ Warnings: <strong>$eventWarnings</strong></div>
  </div>
  $excludedNamespacesHtml
</div>
<div class="container"><h1>Node Conditions & Resources</h1><h2 id="nodecon">Node Conditions <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Displays node readiness, taints, and schedulability.</span></span></h2><div class="table-container">$collapsibleNodeConditionsHtml</div><h2 id="noderesource">Node Resources <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Shows CPU and memory usage across nodes.</span></span></h2><div class="table-container">$collapsibleNodeResourcesHtml</div></div>
<div class="container"><h1 id="namespaces">Namespaces</h1><h2>Empty Namespaces <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Namespaces without any active workloads.</span></span></h2><div class="table-container">$collapsibleEmptyNamespaceHtml</div>
<h2 id="resourceQuotas">ResourceQuota Checks <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Detects namespaces lacking or missing quota definitions.</span></span></h2>
<div class="table-container">$collapsibleResourceQuotasHtml</div>

<h2 id="namespaceLimitRanges">LimitRange Checks <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Detects namespaces missing default resource limits.</span></span></h2>
<div class="table-container">$collapsibleNamespaceLimitRangesHtml</div>
</div>
<div class="container"><h1 id="workloads">Workloads</h1><h2 id="daemonsets">DaemonSets Not Fully Running <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Identifies DaemonSets with unavailable pods or rollout issues.</span></span></h2><div class="table-container">$collapsibleDaemonSetIssuesHtml</div>

<h2 id="deploymentIssues">Deployment Issues <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Identifies Deployments with unhealthy replicas or rollout problems.</span></span></h2>
<div class="table-container">$collapsibleDeploymentIssuesHtml</div>

<h2 id="statefulSetIssues">StatefulSet Issues <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Detects StatefulSets with unavailable pods or replica mismatches.</span></span></h2>
<div class="table-container">$collapsibleStatefulSetIssuesHtml</div>

<h2 id="HPA">Horizontal Pod Autoscalers <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Checks HPA presence and effectiveness.</span></span></h2>
  <div class="table-container">$collapsibleHPAHtml</div>

  <h2 id="missingResourceLimits">Missing Resource Requests & Limits <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Finds containers without memory/CPU requests or limits.</span></span></h2>
  <div class="table-container">$collapsibleMissingResourceLimitsHtml</div>

  <h2 id="PDB">PodDisruptionBudgets <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Detects missing or ineffective PDBs.</span></span></h2>
  <div class="table-container">$collapsiblePDBHtml</div>

  <h2 id="missingProbes">Missing Health Probes <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Reports containers missing readiness/liveness/startup probes.</span></span></h2>
  <div class="table-container">$collapsibleMissingProbesHtml</div>
</div>
<div class="container">
  <h1 id="pods">Pods</h1>

  <h2 id="podrestarts">Pods with High Restarts 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Pods with restarts above the configured threshold.</span>
    </span>
  </h2>
  <div class="table-container">$collapsiblePodsRestartHtml</div>

  <h2 id="podlong">Long Running Pods 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Pods running beyond expected duration (e.g. stuck Jobs).</span>
    </span>
  </h2>
  <div class="table-container">$collapsiblePodLongRunningHtml</div>

  <h2 id="podfail">Failed Pods 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Pods that exited with a non-zero status.</span>
    </span>
  </h2>
  <div class="table-container">$collapsiblePodFailHtml</div>

  <h2 id="podpend">Pending Pods 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Pods pending scheduling or resource allocation.</span>
    </span>
  </h2>
  <div class="table-container">$collapsiblePodPendingHtml</div>

  <h2 id="crashloop">CrashLoopBackOff Pods 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Pods continuously crashing and restarting.</span>
    </span>
  </h2>
  <div class="table-container">$collapsibleCrashloopHtml</div>

  <h2 id="debugpods">Running Debug Pods 
    <span class="tooltip"><span class="info-icon">i</span>
      <span class="tooltip-text">Ephemeral containers or debug pods left running.</span>
    </span>
  </h2>
  <div class="table-container">$collapsibleLeftoverdebugHtml</div>

  <!-- 🔧 Custom checks for Section: Pods -->
  <div class="table-container">$collapsiblePodsHtml</div>
</div>
<div class="container"><h1 id="jobs">Jobs</h1><h2 id="stuckjobs">Stuck Jobs <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Jobs that haven't progressed or completed as expected.</span></span></h2><div class="table-container">$collapsibleStuckJobsHtml</div><h2 id="failedjobs">Job Failures <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Jobs that exceeded retries or failed execution.</span></span></h2><div class="table-container">$collapsibleJobFailHtml</div></div>
<div class="container"><h1 id="networking">Networking</h1><h2 id="servicenoendpoints">Services without Endpoints <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Services that have no active pods backing them.</span></span></h2><div class="table-container">$collapsibleServicesWithoutEndpointsHtml</div><h2 id="publicServices">Publicly Accessible Services <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Services exposed via LoadBalancer or external IPs.</span></span></h2><div class="table-container">$collapsiblePublicServicesHtml</div>
<h2 id="ingressHealth">Ingress Configuration Issues <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Validates Ingress resources for misconfigurations or missing backend services.</span></span></h2>
<div class="table-container">$collapsibleIngressHealthHtml</div>
</div>
<div class="container"><h1 id="storage">Storage</h1><h2 id="unmountedpv">Unmounted Persistent Volumes <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Persistent volumes not currently mounted to any pod.</span></span></h2><div class="table-container">$collapsibleUnmountedpvHtml</div></div>

<div class="container">
  <h1 id="configuration">Configuration Hygiene</h1>
  <div class="table-container">$collapsibleConfigurationHygieneHtml</div>
</div>


<div class="container"><h1 id="security">Security</h1>

<h2 id="rbacmisconfig">RBAC Misconfigurations <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">RoleBindings or ClusterRoleBindings with missing subjects.</span></span></h2>
<div class="table-container">$collapsibleRbacmisconfigHtml</div>

<h2 id="rbacOverexposure">RBAC Overexposure <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Subjects with excessive or unnecessary privileges.</span></span></h2>
<div class="table-container">$collapsibleRbacOverexposureHtml</div>

<h2 id="orphanedRoles">Unused Roles & ClusterRoles <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Roles not referenced by any binding.</span></span></h2>
<div class="table-container">$collapsibleOrphanedRolesHtml</div>

<h2 id="orphanedServiceAccounts">Orphaned ServiceAccounts <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">ServiceAccounts not used by any Pod or Binding.</span></span></h2>
<div class="table-container">$collapsibleOrphanedServiceAccountsHtml</div>

<h2 id="orphanedconfigmaps">Orphaned ConfigMaps <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">ConfigMaps not referenced by any pod or controller.</span></span></h2>
<div class="table-container">$collapsibleOrphanedConfigMapsHtml</div>

<h2 id="orphanedsecrets">Orphaned Secrets <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Secrets that are unused or unmounted by workloads.</span></span></h2>
<div class="table-container">$collapsibleOrphanedSecretsHtml</div>

<h2 id="podsRoot">Pods Running as Root <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Containers running as UID 0.</span></span></h2>
<div class="table-container">$collapsiblePodsRootHtml</div>

<h2 id="privilegedContainers">Privileged Containers <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Containers running with privileged security context.</span></span></h2>
<div class="table-container">$collapsiblePrivilegedContainersHtml</div>

<h2 id="hostPidNet">hostPID / hostNetwork Enabled <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Containers sharing host PID or network namespaces.</span></span></h2>
<div class="table-container">$collapsibleHostPidNetHtml</div>

</div>
<div class="container">
<h1 id="kubeevents">Kubernetes Warning Events</h1>
<h2 id="clusterwarnings">Warning Summary (Grouped) <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Grouped summary of recent Warning and Error events from the cluster.</span></span></h2>
<div class="table-container">$collapsibleEventSummaryWarningsHtml</div>
<h2 id="fulleventlog">Full Warning Event Log <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Detailed log of recent Warning and Error events from the cluster.</span></span></h2>
<div class="table-container">$collapsibleEventSummaryFullLogHtml</div>
</div>
<div class="container">
  <h1 id="customChecks">Custom Kubectl Checks</h1>
  <div class="table-container">$collapsibleCustomChecksHtml</div>
</div>
$aksHealthCheck
<button id="menuFab" title="Open Menu">☰</button>
<footer class="footer">
  <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy Logo" class="logo">
  <p><strong>Report generated by KubeBuddy $version</strong> on $today</p>
  <p>© $year KubeBuddy | <a href="https://kubedeck.io" target="_blank">KubeDeck.io</a></p>
  <p><em>This report is a snapshot of the cluster state at the time of generation. It may not reflect real-time changes. Always verify configurations before making critical decisions.</em></p>
</footer>
<a href="#top" id="backToTop">Back to Top</a>
      <script>
      $jsContent
      </script>
</body>
</html>
"@

  $htmlTemplate | Set-Content $outputPath
}