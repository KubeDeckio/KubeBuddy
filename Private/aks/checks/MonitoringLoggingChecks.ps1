$monitoringLoggingChecks = @(
    @{
        ID          = "AKSMON001";
        Category    = "Monitoring & Logging";
        Name        = "Azure Monitor";
        Value       = { ($clusterInfo.properties.addonProfiles.omsagent).enabled };
        Expected    = $true;
        FailMessage = "Azure Monitor is not enabled. Without it, logging and monitoring data will not be collected.";
        Severity    = "High";
        Recommendation = "Enable Azure Monitor to collect logs and metrics for better observability and troubleshooting.";
        URL         = "https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview";
    },
    @{
        ID             = "AKSMON002";
        Category       = "Monitoring & Logging";
        Name           = "Managed Prometheus Enabled";
        Value          = { $clusterInfo.properties.azureMonitorProfile.metrics.enabled };
        Expected       = $true;
        FailMessage    = "Managed Prometheus is not enabled, meaning AKS metric collection and monitoring are limited.";
        Severity       = "High";
        Recommendation = "Enable Azure Monitor managed Prometheus to collect and store Kubernetes metrics efficiently.";
        URL            = "https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-metrics-overview";
    }
)
