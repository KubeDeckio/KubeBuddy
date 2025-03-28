$Global:MakeReport = $false  # Global flag to control report mode

# $localScripts = Get-ChildItem -Path "$pwd/Private/*.ps1"

# # Execute each .ps1 script found in the local Private directory
# foreach ($script in $localScripts) {
#     Write-Verbose "Executing script: $($script.FullName)"
#     . $script.FullName  # Call the script
# }

$moduleVersion = "v0.0.4"

function Invoke-KubeBuddy {
    param (
        [switch]$HtmlReport,
        [switch]$txtReport,
        [switch]$Aks,
        [switch]$ExcludeNamespaces,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [string]$outputpath
    )
    
    # Assign default value if $outputpath is not set
    if (-not $outputpath) {
        $outputpath = Join-Path -Path $HOME -ChildPath "kubebuddy-report"
    }
    

    # Detect if outputpath is a FILE or DIRECTORY
    $fileExtension = [System.IO.Path]::GetExtension($outputpath)

    if ($fileExtension -in @(".html", ".txt")) {
        # User provided a full file path, extract directory and base name
        $reportDir = Split-Path -Parent $outputpath
        $reportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputpath)
    }
    else {
        # User provided a directory, set default report names
        $reportDir = $outputpath
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $reportBaseName = "kubebuddy-report-$timestamp"

    }

    # Ensure the output directory exists
    if (!(Test-Path -Path $reportDir)) {
        Write-Host "📂 Creating directory: $reportDir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    # Define report file paths based on the given outputpath
    $htmlReportFile = Join-Path -Path $reportDir -ChildPath "$reportBaseName.html"
    $txtReportFile = Join-Path -Path $reportDir -ChildPath "$reportBaseName.txt"
    Clear-Host

    # **KubeBuddy ASCII Art**
    $banner = @"
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗
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

    # Get current context first
    $context = kubectl config view --minify -o jsonpath="{.current-context}"
    Write-Host "`n🤖 Connected to Kubernetes context: '$context'" -ForegroundColor Cyan

    # Confirm before proceeding
    $confirmation = Read-Host "🤖 Is this the correct cluster context? (y/n)"
    if ($confirmation.Trim().ToLower() -ne 'y') {
        Write-Host "🤖 Exiting. Please switch context and try again." -ForegroundColor Yellow
        return
    }

    if ($Aks) {
        Write-Host "`n🤖 Validating AKS cluster access..." -ForegroundColor Yellow
        try {
            $aksInfo = az aks show --resource-group $ResourceGroup --name $ClusterName | ConvertFrom-Json
        }
        catch {
            Write-Host "🤖 ❌ Failed to access AKS cluster '$ClusterName' in '$ResourceGroup'" -ForegroundColor Red
            Write-Host "🤖 Check that you're logged in to Azure and that the cluster exists." -ForegroundColor Red
            return
        }
    
        Write-Host "🤖 ✅ Connected to AKS Cluster: $($aksInfo.name) in $($aksInfo.location)`n" -ForegroundColor Green
    }

    # ========== REPORT MODES ==========

    if ($HtmlReport) {
        Write-Host "📄 Generating HTML report: $htmlReportFile" -ForegroundColor Cyan

        if ($Aks -and (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName)) {
            Write-Host "⚠️ ERROR: -Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName" -ForegroundColor Red
            return
        }

        $KubeData = Get-KubeData -ResourceGroup $ResourceGroup -ClusterName $ClusterName -ExcludeNamespaces:$ExcludeNamespaces -Aks:$Aks

        Generate-K8sHTMLReport `
            -version $moduleVersion `
            -outputPath $htmlReportFile `
            -aks:$Aks `
            -SubscriptionId $SubscriptionId `
            -ResourceGroup $ResourceGroup `
            -ClusterName $ClusterName `
            -ExcludeNamespaces:$ExcludeNamespaces `
            -KubeData $KubeData

        Write-Host "`n🤖 ✅ HTML report saved at: $htmlReportFile" -ForegroundColor Green
        return
    }

    if ($txtReport) {
        Write-Host "📄 Generating Text report: $txtReportFile" -ForegroundColor Cyan

        $KubeData = Get-KubeData -ResourceGroup $ResourceGroup -ClusterName $ClusterName -ExcludeNamespaces:$ExcludeNamespaces -Aks:$Aks

        Generate-K8sTextReport `
            -ReportFile $txtReportFile `
            -ExcludeNamespaces:$ExcludeNamespaces `
            -KubeData $KubeData

        Write-Host "`n🤖 ✅ Text report saved at: $txtReportFile" -ForegroundColor Green
        return
    }

    # ========== INTERACTIVE MODE ==========
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
