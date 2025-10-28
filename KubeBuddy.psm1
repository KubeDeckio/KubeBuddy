# Ensure powershell-yaml module is installed
$requiredModule = 'powershell-yaml'
if (-not (Get-Module -ListAvailable -Name $requiredModule)) {
    Write-Host "Installing required module: $requiredModule..." -ForegroundColor Yellow
    try {
        # Ensure PSGallery is trusted
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }
        Install-Module -Name $requiredModule -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "$requiredModule installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install $requiredModule. Error: $_"
        throw "Module installation failed. Please install $requiredModule manually using 'Install-Module $requiredModule -AllowClobber'."
    }
}

# Import powershell-yaml
try {
    Import-Module -Name powershell-yaml -ErrorAction Stop
}
catch {
    Write-Error "Failed to import $requiredModule. Error: $_"
    throw "Module import failed. Ensure $requiredModule is installed and accessible."
}

# Load all private functions (not exported) - exclude test files
$privateScripts = Get-ChildItem -Path "$PSScriptRoot/Private" -Recurse -File -Filter "*.ps1" | 
    Where-Object { $_.Name -notlike "*Test*" -and $_.Name -notlike "*test*" }
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