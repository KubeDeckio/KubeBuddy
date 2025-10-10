# EKS Individual Check Testing
# Test specific EKS checks in isolation

param(
    [string]$CheckCategory = "Security", # Security, Networking, BestPractices, etc.
    [switch]$ListCategories
)

if ($ListCategories) {
    Write-Host "Available EKS Check Categories:" -ForegroundColor Cyan
    Write-Host "- Security" -ForegroundColor Yellow
    Write-Host "- IdentityAndAccess" -ForegroundColor Yellow
    Write-Host "- Networking" -ForegroundColor Yellow
    Write-Host "- BestPractices" -ForegroundColor Yellow
    Write-Host "- MonitoringLogging" -ForegroundColor Yellow
    Write-Host "- ResourceManagement" -ForegroundColor Yellow
    Write-Host "- DisasterRecovery" -ForegroundColor Yellow
    return
}

# Load mock data
. (Join-Path $PSScriptRoot "Test-EKSMockData.ps1")

# Load check files
$checksFolder = Join-Path -Path $PSScriptRoot -ChildPath "checks"
$checkFile = Join-Path -Path $checksFolder -ChildPath "${CheckCategory}Checks.ps1"

if (-not (Test-Path $checkFile)) {
    Write-Error "Check file not found: $checkFile"
    Write-Host "Available files:" -ForegroundColor Yellow
    Get-ChildItem $checksFolder -Filter "*Checks.ps1" | ForEach-Object { Write-Host "  - $($_.BaseName)" -ForegroundColor Cyan }
    return
}

# Load the specific check file
Write-Host "Loading checks from: $checkFile" -ForegroundColor Cyan
. $checkFile

# Get the checks variable (e.g., $securityChecks, $networkingChecks)
$checksVariableName = "${CheckCategory}Checks".ToLower()
$checks = Get-Variable -Name $checksVariableName -ErrorAction SilentlyContinue

if (-not $checks) {
    Write-Error "No checks variable found with name: $checksVariableName"
    return
}

# Generate mock data
$mockData = New-MockEKSClusterData
$mockClusterInfo = $mockData.EksCluster

# Set up the clusterInfo variable that checks expect
$clusterInfo = $mockClusterInfo

Write-Host "`n🧪 Testing $CheckCategory Checks" -ForegroundColor Green
Write-Host "=" * 40 -ForegroundColor Green

# Test each check
foreach ($check in $checks.Value) {
    Write-Host "`n📋 Testing: $($check.ID) - $($check.Name)" -ForegroundColor Yellow
    
    try {
        # Execute the check's Value scriptblock
        $result = & $check.Value
        
        $status = if ($result -eq $check.Expected) { "✅ PASS" } else { "❌ FAIL" }
        $statusColor = if ($result -eq $check.Expected) { "Green" } else { "Red" }
        
        Write-Host "   Result: $result | Expected: $($check.Expected) | $status" -ForegroundColor $statusColor
        
        if ($result -ne $check.Expected) {
            Write-Host "   FailMessage: $($check.FailMessage)" -ForegroundColor DarkRed
            Write-Host "   Recommendation: $($check.Recommendation)" -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Host "   ❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n✅ Testing completed for $CheckCategory checks!" -ForegroundColor Cyan