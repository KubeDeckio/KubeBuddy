$Global:MakeReport = $false  # Global flag to control report mode

$moduleVersion = "v0.0.4"

function Invoke-KubeBuddy {
    param (
        [switch]$HtmlReport,
        [switch]$txtReport,
        [switch]$jsonReport,
        [switch]$Aks,
        [switch]$ExcludeNamespaces,
        [switch]$yes,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [string]$outputpath,
        [switch]$UseAksRestApi, # Flag for AKS REST API mode
        [switch]$IncludePrometheus, # Flag to include Prometheus data
        [string]$PrometheusUrl, # Prometheus endpoint
        [string]$PrometheusMode, # Authentication mode: local, basic, bearer, azure
        [string]$PrometheusBearerTokenEnv,  # Environment variable for bearer token
        [System.Management.Automation.PSCredential]$PrometheusCredential # Credential for Prometheus basic auth
    )

    # Assign default value if $outputpath is not set
    if (-not $outputpath) {
        $outputpath = Join-Path -Path $HOME -ChildPath "kubebuddy-report"
    }

    # Detect if outputpath is a FILE or DIRECTORY
    $fileExtension = [System.IO.Path]::GetExtension($outputpath)

    if ($fileExtension -in @(".html", ".txt")) {
        $reportDir = Split-Path -Parent $outputpath
        $reportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputpath)
    }
    else {
        $reportDir = $outputpath
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $reportBaseName = "kubebuddy-report-$timestamp"
    }

    Install-Module -Name PSAI

Import-module -Name PSAI

    # Ensure the output directory exists
    if (!(Test-Path -Path $reportDir)) {
        Write-Host "📂 Creating directory: $reportDir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    # Define report file paths
    $htmlReportFile = Join-Path -Path $reportDir -ChildPath "$reportBaseName.html"
    $txtReportFile = Join-Path -Path $reportDir -ChildPath "$reportBaseName.txt"
    $jsonReportFile = Join-Path -Path $reportDir -ChildPath "$reportBaseName.json"
    Clear-Host

    # KubeBuddy ASCII Art
    $banner = @"
██╗  ██╗██╗   ██║██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝
█████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║██║  ██║██║  ██║ ╚████╔╝ 
██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║  ██║██║  ██║  ╚██╔╝  
██║  ██╗╚██████╔╝██████╔╝███████╗██████╔╝╚██████╔╝██████╔╝██████╔╝   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝    ╚═╝   
"@
    Write-Host ""
    Write-Host -NoNewline $banner -ForegroundColor Cyan
    Write-Host "$moduleVersion" -ForegroundColor Magenta
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Your Kubernetes Assistant" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray

    # Get current context
    $context = kubectl config view --minify -o jsonpath="{.current-context}" 2>$null
    if (-not $context) {
        Write-Host "`n🚫 Failed to get Kubernetes context. Ensure kubeconfig is valid and cluster is accessible." -ForegroundColor Red
        return
    }
    Write-Host "`n🤖 Connected to Kubernetes context: '$context'" -ForegroundColor Cyan

    # Confirm context
    if ($yes) {
        Write-Host "`n🤖 Skipping context confirmation." -ForegroundColor Red
    }
    else {
        $confirmation = Read-Host "🤖 Is this the correct context? (y/n)"
        if ($confirmation.Trim().ToLower() -ne 'y') {
            Write-Host "🤖 Exiting. Please switch context and try again." -ForegroundColor Yellow
            return
        }
    }

    # Validate cluster access for AKS
    if ($Aks) {
        Write-Host -NoNewline "`n🤖 Validating AKS cluster access..." -ForegroundColor Yellow
        $spnProvided = $env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID
        $isContainer = Test-IsContainer

        if (-not $isContainer) {
            # Local run: Use az aks show
            try {
                if ($spnProvided) {
                    az login --service-principal -u $env:AZURE_CLIENT_ID -p $env:AZURE_CLIENT_SECRET --tenant $env:AZURE_TENANT_ID --only-show-errors 2>&1 | Out-Null
                    $aksOutput = az aks show --resource-group $ResourceGroup --name $ClusterName --subscription $SubscriptionId --only-show-errors 2>&1
                    az logout --only-show-errors 2>&1 | Out-Null
                }
                else {
                    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
                        Write-Host "`r🤖 ❌ Azure CLI not found and no SPN credentials provided." -ForegroundColor Red
                        return
                    }
                    $aksOutput = az aks show --resource-group $ResourceGroup --name $ClusterName --subscription $SubscriptionId --only-show-errors 2>&1
                }
                if ($LASTEXITCODE -ne 0 -or -not $aksOutput) {
                    Write-Host "`r🤖 ❌ Failed to access AKS cluster '$ClusterName' in '$ResourceGroup'" -ForegroundColor Red
                    Write-Host "🤖 Ensure you're logged in to Azure with 'az login' or provide SPN credentials." -ForegroundColor Red
                    Write-Host "🧾 Error: $aksOutput" -ForegroundColor DarkGray
                    return
                }
                $aksInfo = $aksOutput | ConvertFrom-Json
                Write-Host "`r🤖 ✅ Connected to AKS Cluster: $($aksInfo.name) in $($aksInfo.location)`n" -ForegroundColor Green
            }
            catch {
                Write-Host "`r🤖 ❌ Failed to access AKS cluster: $_" -ForegroundColor Red
                return
            }
        }
        else {
            # Container run: Use kubectl check
            try {
                $kubectlOutput = kubectl get nodes --no-headers 2>&1
                if (
                    $LASTEXITCODE -ne 0 -or
                    $kubectlOutput -match "Unable to connect to the server" -or
                    $kubectlOutput -match "no such host" -or
                    $kubectlOutput -match "couldn't get current server API group list" -or
                    $kubectlOutput -match "get token" -or
                    $kubectlOutput -match "credentials"
                ) {
                    Write-Host "`r🤖 ❌ Failed to access AKS cluster. Check DNS resolution, SPN permissions, or kubeconfig auth." -ForegroundColor Red
                    Write-Host "🧾 Error: $kubectlOutput" -ForegroundColor DarkGray
                    return
                }
            
                Write-Host "`r🤖 ✅ Connected to AKS cluster.    `n" -ForegroundColor Green
            }
            catch {
                Write-Host "`r🤖 ❌ Exception occurred while validating cluster access: $_" -ForegroundColor Red
                return
            }            
        }
    }

    # Report modes
    if ($HtmlReport) {
        Write-Host "📄 Generating HTML report: $htmlReportFile" -ForegroundColor Cyan
        if ($Aks -and (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName)) {
            Write-Host "⚠️ ERROR: -Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName" -ForegroundColor Red
            return
        }
        $kubeDataParams = @{
            SubscriptionId           = $SubscriptionId
            ResourceGroup            = $ResourceGroup
            ClusterName              = $ClusterName
            ExcludeNamespaces        = $ExcludeNamespaces
            Aks                      = $Aks
            UseAksRestApi            = $UseAksRestApi
            
        }
        
        # Add Prometheus params only if IncludePrometheus is true
        if ($IncludePrometheus) {
            $kubeDataParams.IncludePrometheus        = $IncludePrometheus
            $kubeDataParams.PrometheusUrl            = $PrometheusUrl
            $kubeDataParams.PrometheusMode           = $PrometheusMode
            $kubeDataParams.PrometheusBearerTokenEnv = $PrometheusBearerTokenEnv
            if ($PrometheusCredential) {
                $kubeDataParams.PrometheusCredential = $PrometheusCredential
            }
        }
        
        $KubeData = Get-KubeData @kubeDataParams
        
        if ($KubeData -eq $false) {
            Write-Host "`n🚫 Script terminated due to a connection error. Please ensure you can connect to your Kubernetes Cluster" -ForegroundColor Red
            return
        }

        Generate-K8sHTMLReport `
            -version $moduleVersion `
            -outputPath $htmlReportFile `
            -aks:$Aks `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $ResourceGroup `
            -ClusterName $ClusterName `
            -ExcludeNamespaces:$ExcludeNamespaces `
            -KubeData $KubeData
            
        # Verify that the HTML file was actually created
        if (Test-Path -Path $htmlReportFile) {
            Write-Host "`n🤖 ✅ HTML report saved at: $htmlReportFile" -ForegroundColor Green
        }
        else {
            Write-Host "`n🚫 Failed to generate the HTML report. Please check for errors above." -ForegroundColor Red
        }
        return
    }

    if ($txtReport) {
        Write-Host "📄 Generating Text report: $txtReportFile" -ForegroundColor Cyan
        if ($Aks -and (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName)) {
            Write-Host "⚠️ ERROR: -Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName" -ForegroundColor Red
            return
        }
        $kubeDataParams = @{
            SubscriptionId           = $SubscriptionId
            ResourceGroup            = $ResourceGroup
            ClusterName              = $ClusterName
            ExcludeNamespaces        = $ExcludeNamespaces
            Aks                      = $Aks
            UseAksRestApi            = $UseAksRestApi
            
        }
        
        # Add Prometheus params only if IncludePrometheus is true
        if ($IncludePrometheus) {
            $kubeDataParams.IncludePrometheus        = $IncludePrometheus
            $kubeDataParams.PrometheusUrl            = $PrometheusUrl
            $kubeDataParams.PrometheusMode           = $PrometheusMode
            $kubeDataParams.PrometheusBearerTokenEnv = $PrometheusBearerTokenEnv
            if ($PrometheusCredential) {
                $kubeDataParams.PrometheusCredential = $PrometheusCredential
            }
        }
        
        $KubeData = Get-KubeData @kubeDataParams
        
        if ($KubeData -eq $false) {
            Write-Host "`n🚫 Script terminated due to a connection error. Please ensure you can connect to your Kubernetes Cluster" -ForegroundColor Red
            return
        }

        Generate-K8sTextReport `
            -ReportFile $txtReportFile `
            -ExcludeNamespaces:$ExcludeNamespaces `
            -aks:$Aks `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $ResourceGroup `
            -ClusterName $ClusterName `
            -KubeData $KubeData
            
        Write-Host "`n🤖 ✅ Text report saved at: $txtReportFile" -ForegroundColor Green
        return
    }

    if ($jsonReport) {
        Write-Host "📄 Generating Json report: $jsonReportFile" -ForegroundColor Cyan
        if ($Aks -and (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName)) {
            Write-Host "⚠️ ERROR: -Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName" -ForegroundColor Red
            return
        }

        $kubeDataParams = @{
            SubscriptionId           = $SubscriptionId
            ResourceGroup            = $ResourceGroup
            ClusterName              = $ClusterName
            ExcludeNamespaces        = $ExcludeNamespaces
            Aks                      = $Aks
            UseAksRestApi            = $UseAksRestApi
            
        }
        
        # Add Prometheus params only if IncludePrometheus is true
        if ($IncludePrometheus) {
            $kubeDataParams.IncludePrometheus        = $IncludePrometheus
            $kubeDataParams.PrometheusUrl            = $PrometheusUrl
            $kubeDataParams.PrometheusMode           = $PrometheusMode
            $kubeDataParams.PrometheusBearerTokenEnv = $PrometheusBearerTokenEnv
            if ($PrometheusCredential) {
                $kubeDataParams.PrometheusCredential = $PrometheusCredential
            }
        }
        
        $KubeData = Get-KubeData @kubeDataParams
        
        if ($KubeData -eq $false) {
            Write-Host "`n🚫 Script terminated due to a connection error. Please ensure you can connect to your Kubernetes Cluster" -ForegroundColor Red
            return
        }

        Create-jsonReport `
            -outputpath $jsonReportFile `
            -KubeData $KubeData `
            -ExcludeNamespaces:$ExcludeNamespaces `
            -aks:$Aks `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $ResourceGroup `
            -ClusterName $ClusterName

        Write-Host "`n🤖 ✅ Json report saved at: $jsonReportFile" -ForegroundColor Green
        return
    }

    # Interactive mode
    Write-Host -NoNewline "`n`r🤖 Initializing KubeBuddy..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    Write-Host "`r✅ KubeBuddy is ready to assist you!  " -ForegroundColor Green
    $msg = @(
        "🤖 Hello, I'm KubeBuddy—your Kubernetes assistant!",
        "",
        "   - I can check node health, workload status, networking, storage, RBAC security, and more.",
        "   - You're currently connected to the '$context' context. All actions will run on this cluster.",
        "",
        "                        ** WARNING: PLEASE VERIFY YOUR CONTEXT! **",
        "",
        "   - If this is NOT the correct CONTEXT, please EXIT and connect to the correct one.",
        "   - Actions performed here may impact the wrong Kubernetes cluster!",
        "",
        "  - Choose an option from the menu below to get started."
    )
    Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Green" -delay 50
    $firstRun = $true
    show-mainMenu -ExcludeNamespaces:$ExcludeNamespaces -KubeData $KubeData
}