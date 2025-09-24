$monitoringLoggingChecks = @(
    @{
        ID          = "AKSMON001";
        Category    = "Monitoring & Logging";
        Name        = "Azure Monitor";
        Value       = { ($clusterInfo.properties.addonProfiles.omsagent).enabled };
        Expected    = $true;
        FailMessage = "Azure Monitor Container Insights is disabled, providing no visibility into container performance, resource utilization, pod failures, or cluster health. This eliminates troubleshooting capabilities, prevents proactive monitoring, and makes root cause analysis nearly impossible during incidents.";
        Severity    = "High";
        Recommendation = "Enable Azure Monitor Container Insights using 'az aks enable-addons --resource-group <rg> --name <cluster> --addons monitoring --workspace-resource-id <workspace-id>' or through Azure Portal > Monitoring > Insights. Configure log retention (90+ days) and set up alerts for container failures and resource usage.";
        URL         = "https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview";
    },
    @{
        ID             = "AKSMON002";
        Category       = "Monitoring & Logging";
        Name           = "Managed Prometheus Enabled";
        Value          = { $clusterInfo.properties.azureMonitorProfile.metrics.enabled };
        Expected       = $true;
        FailMessage    = "Azure Monitor managed Prometheus is disabled, missing critical Kubernetes-native metrics for workload performance, resource utilization trends, and application-specific monitoring. This limits observability to basic infrastructure metrics and prevents comprehensive performance analysis and capacity planning.";
        Severity       = "High";
        Recommendation = "Enable managed Prometheus using 'az aks update --resource-group <rg> --name <cluster> --enable-azure-monitor-metrics' or via Azure Portal > Monitoring > Insights. Consider integrating with Azure Managed Grafana for advanced dashboards and setting up alerting rules for critical metrics.";
        URL            = "https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-metrics-overview";
    }
)
