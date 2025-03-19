# KubeBuddy.psm1

# Make sure we're in the module directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load all private functions (not exported)
$privateScripts = Get-ChildItem -Path  "$scriptPath\Private\*.ps1" -Recurse -File
foreach ($script in $privateScripts) {
    . $script.FullName
}

# Load all public functions (exported)
$publicScripts = Get-ChildItem -Path  "$scriptPath\Public\*.ps1" -Recurse -File
foreach ($script in $publicScripts) {
    . $script.FullName
}

# Export public functions
Export-ModuleMember -Function @( 
    'Invoke-KubeBuddy'
    'Invoke-AKSBestPractices'
    'Get-AKSClusterInfo'
)
