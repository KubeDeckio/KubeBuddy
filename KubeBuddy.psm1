# Load all private functions (not exported)
$privateScripts = Get-ChildItem -Path "$PSScriptRoot/Private" -Recurse -File -Filter "*.ps1"
foreach ($script in $privateScripts) {
    . $script.FullName
}

# Load all public functions (exported)
$publicScripts = Get-ChildItem -Path "$PSScriptRoot/Public" -Recurse -File -Filter "*.ps1"
foreach ($script in $publicScripts) {
    . $script.FullName
}

# Export public functions
Export-ModuleMember -Function 'Invoke-KubeBuddy'