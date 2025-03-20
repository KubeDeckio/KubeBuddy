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

    # **HTML Report with Optional AKS Check**
    if ($HtmlReport) {
        Write-Host "📄 Generating HTML report: $htmlReportFile" -ForegroundColor Cyan
        
        if ($Aks) {
            # Ensure required parameters for AKS are provided
            if (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName) {
                Write-Host "⚠️ ERROR: -Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName" -ForegroundColor Red
                return
            }
            Generate-K8sHTMLReport -version $moduleVersion -outputPath $htmlReportFile -aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
        }
        else {
            Generate-K8sHTMLReport -version $moduleVersion -outputPath $htmlReportFile
        }

        Write-Host "`n🤖 ✅ HTML report saved at: $htmlReportFile" -ForegroundColor Green
        return
    }

    # **TXT Report Generation**
    if ($txtReport) {
        Write-Host "📄 Generating Text report: $txtReportFile" -ForegroundColor Cyan
        Generate-K8sTextReport -ReportFile $txtReportFile
        Write-Host "`n🤖 ✅ Text report saved at: $txtReportFile" -ForegroundColor Green
        return
    }

    # Get the current Kubernetes context
    $context = kubectl config view --minify -o jsonpath="{.current-context}"



    # Thinking animation
    Write-Host -NoNewline "`r🤖 Initializing KubeBuddy..." -ForegroundColor Yellow
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
    show-mainMenu
}
