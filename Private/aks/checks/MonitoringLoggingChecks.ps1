$monitoringLoggingChecks = @(
    @{
        ID          = "BP020";
        Category    = "Monitoring & Logging";
        Name        = "Azure Monitor";
        Value       = ($clusterInfo.addonProfiles.omsagent).enabled;
        Expected    = $true;
        FailMessage = "Enable Azure Monitor for logging and monitoring."
    },
    @{
        ID             = "BP041";
        Category       = "Monitoring & Logging";
        Name           = "Managed Prometheus Enabled";
        Value          = $clusterInfo.azureMonitorProfile.metrics.enabled;
        Expected       = $true;
        FailMessage    = "Managed Prometheus is not enabled. Ensure azureMonitorProfile.metrics.enabled is set to true.";
        Severity       = "High";
        Recommendation = "Enable Azure Monitor metrics to activate managed Prometheus.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/azure-monitor"
    }
)
