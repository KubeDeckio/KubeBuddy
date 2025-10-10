$monitoringLoggingChecks = @(
    @{
        ID         = "EKSMON001";
        Category   = "Monitoring & Logging";
        Name       = "CloudWatch Container Insights Enabled";
        Value      = { 
            # Check if CloudWatch agent/Fluent Bit is deployed
            $cloudWatchAgent = kubectl get daemonset cloudwatch-agent -n amazon-cloudwatch -o json 2>/dev/null | ConvertFrom-Json
            $fluentBit = kubectl get daemonset fluent-bit -n amazon-cloudwatch -o json 2>/dev/null | ConvertFrom-Json
            $cloudWatchAgent -or $fluentBit
        };
        Expected   = $true;
        FailMessage = "CloudWatch Container Insights is not enabled, missing comprehensive monitoring of cluster performance metrics, container logs, and resource utilization data that's essential for troubleshooting and optimization.";
        Severity    = "High";
        Recommendation = "Enable Container Insights using 'aws eks update-cluster-config --name <cluster> --logging enable=api,audit,authenticator,controllerManager,scheduler' and deploy CloudWatch agent with 'kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml'.";
        URL         = "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html";
    },
    @{
        ID         = "EKSMON002";
        Category   = "Monitoring & Logging";
        Name       = "Control Plane Logging Enabled";
        Value      = { 
            $logging = $clusterInfo.Logging.ClusterLogging
            $enabledTypes = $logging | Where-Object { $_.Enabled -eq $true }
            $enabledTypes.Count -ge 3 # At least 3 of the 5 log types should be enabled
        };
        Expected   = $true;
        FailMessage = "EKS control plane logging is not properly configured, missing crucial audit trails and diagnostic information for API server, scheduler, controller manager, authenticator, and audit events.";
        Severity    = "High";
        Recommendation = "Enable control plane logging for critical components using 'aws eks update-cluster-config --name <cluster> --logging enable=api,audit,authenticator,controllerManager,scheduler'. Focus on enabling at least API, audit, and authenticator logs for security monitoring.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html";
    },
    @{
        ID         = "EKSMON003";
        Category   = "Monitoring & Logging";
        Name       = "Metrics Server Deployed";
        Value      = { 
            $metricsServer = kubectl get deployment metrics-server -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $metricsServer -ne $null
        };
        Expected   = $true;
        FailMessage = "Metrics Server is not deployed, preventing HPA (Horizontal Pod Autoscaler), VPA (Vertical Pod Autoscaler), and kubectl top commands from functioning properly due to missing resource usage metrics.";
        Severity    = "Medium";
        Recommendation = "Deploy metrics-server addon using 'aws eks create-addon --cluster-name <cluster> --addon-name metrics-server' or manually install with 'kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html";
    },
    @{
        ID         = "EKSMON004";
        Category   = "Monitoring & Logging";
        Name       = "Application Performance Monitoring";
        Value      = { 
            # Check for common APM solutions (Prometheus, Jaeger, X-Ray)
            $prometheus = kubectl get namespace prometheus -o json 2>/dev/null | ConvertFrom-Json
            $jaeger = kubectl get namespace jaeger -o json 2>/dev/null | ConvertFrom-Json
            $xrayDaemon = kubectl get daemonset xray-daemon -n default -o json 2>/dev/null | ConvertFrom-Json
            $adotCollector = kubectl get deployment adot-collector -o json 2>/dev/null | ConvertFrom-Json
            
            $prometheus -or $jaeger -or $xrayDaemon -or $adotCollector
        };
        Expected   = $true;
        FailMessage = "No application performance monitoring (APM) solution is deployed, lacking visibility into application performance, distributed tracing, and custom metrics collection for effective troubleshooting and optimization.";
        Severity    = "Medium";
        Recommendation = "Deploy an APM solution like AWS X-Ray with ADOT collector, Prometheus with Grafana, or Jaeger for distributed tracing. For AWS X-Ray, use 'kubectl apply -f https://amazon-eks.s3.us-west-2.amazonaws.com/docs/addons/adot/latest/adot-collector-advanced.yaml'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/deploy-adot.html";
    },
    @{
        ID         = "EKSMON005";
        Category   = "Monitoring & Logging";
        Name       = "Log Aggregation Configured";
        Value      = { 
            # Check for log aggregation solutions
            $fluentd = kubectl get daemonset fluentd -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $fluentBit = kubectl get daemonset fluent-bit -n amazon-cloudwatch -o json 2>/dev/null | ConvertFrom-Json
            $logstash = kubectl get deployment logstash -o json 2>/dev/null | ConvertFrom-Json
            
            $fluentd -or $fluentBit -or $logstash
        };
        Expected   = $true;
        FailMessage = "Log aggregation is not properly configured, making it difficult to centralize, search, and analyze application and system logs across the cluster for troubleshooting and compliance.";
        Severity    = "Medium";
        Recommendation = "Configure log aggregation using Fluent Bit to send logs to CloudWatch, or deploy Fluentd/Logstash for custom log processing. Use AWS for Fluent Bit addon or install manually for centralized logging.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html";
    },
    @{
        ID         = "EKSMON006";
        Category   = "Monitoring & Logging";
        Name       = "Alerting Rules Configured";
        Value      = { 
            # Check for alerting configurations (Prometheus AlertManager, CloudWatch Alarms)
            $alertManager = kubectl get deployment alertmanager -o json 2>/dev/null | ConvertFrom-Json
            $prometheusRules = kubectl get prometheusrule --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            
            $alertManager -or ($prometheusRules.items.Count -gt 0)
        };
        Expected   = $true;
        FailMessage = "Alerting rules are not configured for cluster and application monitoring, missing proactive notifications about critical issues that could lead to service disruptions or performance degradation.";
        Severity    = "Medium";
        Recommendation = "Configure alerting rules for critical metrics like high CPU/memory usage, pod restart rates, failed deployments, and node health. Use Prometheus AlertManager or CloudWatch Alarms with SNS for notifications.";
        URL         = "https://prometheus.io/docs/alerting/latest/alertmanager/";
    },
    @{
        ID         = "EKSMON007";
        Category   = "Monitoring & Logging";
        Name       = "Node and Pod Monitoring";
        Value      = { 
            # Check if node exporter or similar monitoring is deployed
            $nodeExporter = kubectl get daemonset node-exporter -o json 2>/dev/null | ConvertFrom-Json
            $prometheusNodeExporter = kubectl get daemonset prometheus-node-exporter -o json 2>/dev/null | ConvertFrom-Json
            
            $nodeExporter -or $prometheusNodeExporter
        };
        Expected   = $true;
        FailMessage = "Node and pod-level monitoring is not configured, lacking detailed visibility into resource usage, performance metrics, and health status at the infrastructure level.";
        Severity    = "Medium";
        Recommendation = "Deploy node monitoring using Prometheus Node Exporter with 'kubectl apply -f https://raw.githubusercontent.com/prometheus/node_exporter/master/examples/systemd/node_exporter.service' or use CloudWatch agent for AWS-native monitoring.";
        URL         = "https://github.com/prometheus/node_exporter";
    },
    @{
        ID         = "EKSMON008";
        Category   = "Monitoring & Logging";
        Name       = "Audit Log Analysis";
        Value      = { 
            # Check if audit logs are being analyzed or processed
            $auditLogging = $clusterInfo.Logging.ClusterLogging | Where-Object { $_.Types -contains "audit" -and $_.Enabled -eq $true }
            # Basic check - if audit logging is enabled, assume some analysis is possible
            $auditLogging -ne $null
        };
        Expected   = $true;
        FailMessage = "Kubernetes audit logs are not being collected or analyzed, missing critical security monitoring capabilities for API server access, resource modifications, and potential security incidents.";
        Severity    = "High";
        Recommendation = "Enable audit logging in EKS control plane logging and set up log analysis using CloudWatch Insights, AWS Security Hub, or SIEM solutions. Use queries to detect suspicious API activities, privilege escalations, and unauthorized access attempts.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html";
    }
)