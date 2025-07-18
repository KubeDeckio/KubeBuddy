@{
    # General
    ModuleVersion = '0.0.4'
    GUID             = 'e3c5b9f4-68d6-4e71-87e2-16bb7bbd8c5c'
    Author = 'Richard Hooper'
    CompanyName = 'Pixel Robots'
    Copyright = '(c) Richard Hooper. All rights reserved.'
    Description      = 'KubeBuddy - A Kubernetes assistant for PowerShell.'

    # PowerShell Version Compatibility
    PowerShellVersion = '7.0'

    # Root module file
    RootModule       = 'KubeBuddy.psm1'

    # Functions exported (only public ones)
    FunctionsToExport = @('Invoke-KubeBuddy')

    # Cmdlets and Variables (not used, so set to empty)
    CmdletsToExport   = @()
    VariablesToExport = @()

    # Paths to scripts
    PrivateData = @{
        PSData = @{
            Tags         = @('Kubernetes', 'K8s', 'Monitoring', 'Reporting', 'KubeDeck', 'best-practices', 'DevOps', 'PowerShell', 'health-checks', 'kube-buddy')
            License     = 'MIT'
            LicenseUri   = 'https://github.com/kubedeckio/kubebuddy?tab=MIT-1-ov-file'
            ProjectUri   = 'https://kubebuddy.io'
            ReleaseNotes = 'https://kubebuddy.kubedeck.io/changelog/'
        }
    }
}
