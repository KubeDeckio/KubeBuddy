# Simple EKS Test Runner
# Run this script to test EKS checks without a real cluster

# Load the mock data generator
. (Join-Path $PSScriptRoot "Test-EKSMockData.ps1")

# Test 1: Healthy cluster (should mostly pass)
Write-Host "`n🧪 TEST 1: Healthy EKS Cluster Configuration" -ForegroundColor Green
Write-Host "=" * 50 -ForegroundColor Green

$healthyResults = Test-EKSChecksWithMockData -Verbose
Write-Host "Healthy cluster test completed.`n" -ForegroundColor Green

# Test 2: Problematic cluster (should show failures)
Write-Host "`n🧪 TEST 2: EKS Cluster with Common Issues" -ForegroundColor Yellow
Write-Host "=" * 50 -ForegroundColor Yellow

$problematicResults = Test-EKSChecksWithMockData -WithIssues -Verbose
Write-Host "Problematic cluster test completed.`n" -ForegroundColor Yellow

Write-Host "✅ All EKS mock tests completed!" -ForegroundColor Cyan