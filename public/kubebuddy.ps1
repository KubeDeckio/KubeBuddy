$Global:MakeReport = $false  # Global flag to control report mode

$localScripts = Get-ChildItem -Path "$pwd/Private/*.ps1"

# Execute each .ps1 script found in the local Private directory
foreach ($script in $localScripts) {
    Write-Verbose "Executing script: $($script.FullName)"
    . $script.FullName  # Call the script
}

$version = "v0.0.3"

function Invoke-KubeBuddy {
    param (
        [switch]$HtmlReport,
        [switch]$txtReport,
        [string]$outputpath = "$HOME\kubebuddy-report"
    )
# Ensure the output directory exists
if (!(Test-Path -Path $outputpath)) {
    Write-Host "📂 Creating directory: $outputpath" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $outputpath -Force | Out-Null
}

# Define report file paths
$htmlReportFile = "$outputpath\kubebuddy-report.html"
$txtReportFile = "$outputpath\kubebuddy-report.txt"

Clear-Host

if ($HtmlReport) {
    Write-Host "📄 Generating HTML report: $htmlReportFile" -ForegroundColor Cyan
    Generate-K8sHTMLReport -version $version -outputPath $htmlReportFile
    Write-Host "`n🤖 ✅ HTML report saved at: $htmlReportFile" -ForegroundColor Green
    return
}

if ($txtReport) {
    Write-Host "📄 Generating Text report: $txtReportFile" -ForegroundColor Cyan
    Generate-K8sTextReport -ReportFile $txtReportFile
    Write-Host "`n🤖 ✅ Text report saved at: $txtReportFile" -ForegroundColor Green
    return
}

    $banner = @"
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝
█████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║██║  ██║██║  ██║ ╚████╔╝ 
██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║  ██║██║  ██║  ╚██╔╝  
██║  ██╗╚██████╔╝██████╔╝███████╗██████╔╝╚██████╔╝██████╔╝██████╔╝   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝    ╚═╝   
"@

    # KubeBuddy ASCII Art
    Write-Host ""
    Write-Host -NoNewline $banner -ForegroundColor Cyan
    write-host "$version" -ForegroundColor Magenta
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Your Kubernetes Assistant" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray

    # Thinking animation
    Write-Host -NoNewline "`r🤖 Initializing KubeBuddy..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2  
    Write-Host "`r✅ KubeBuddy is ready to assist you!  " -ForegroundColor Green


    $msg = @(
        "🤖 Hello, I'm KubeBuddy! Your friendly Kubernetes assistant.",
        "",
        "   - I can help you check node health, workload status, networking, storage, RBAC security, and more.",
        "  - Select an option from the menu below to begin!"
    )

    Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Green" -delay 50

    $firstRun = $true  # Flag to track first execution
    show-mainMenu
}
