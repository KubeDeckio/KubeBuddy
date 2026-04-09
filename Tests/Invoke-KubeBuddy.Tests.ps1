# Tests/Invoke-KubeBuddy.Tests.ps1

# 1. Force‑reload your module under test
$modulePath = Join-Path $PSScriptRoot '..\KubeBuddy.psm1'
Import-Module $modulePath -Force

Describe 'Invoke-KubeBuddy' {

    Context 'HTML Report mode' {

        BeforeAll {
            function global:kubectl {
                'docker-desktop'
            }

            # module‑private helpers
            Mock -CommandName Get-KubeData -ModuleName KubeBuddy -MockWith { @{ dummy = $true } }
            Mock -CommandName Generate-K8sHTMLReport -ModuleName KubeBuddy
            Mock -CommandName Clear-Host -ModuleName KubeBuddy
            Mock -CommandName Clear-KubeBuddyConfigPathOverride -ModuleName KubeBuddy
            Mock -CommandName Clear-ExcludedNamespacesOverride -ModuleName KubeBuddy
            Mock -CommandName Get-ExcludedNamespaces -ModuleName KubeBuddy -MockWith { @() }
            Mock -CommandName Resolve-KubeBuddyRadarSettings -ModuleName KubeBuddy -MockWith {
                @{
                    enabled = $false
                    upload_enabled = $false
                    compare_enabled = $false
                }
            }
        }

        It 'Calls Get-KubeData and Generate-K8sHTMLReport on -HtmlReport' {
            # simulate that the HTML file appears
            Mock -CommandName Test-Path -ModuleName KubeBuddy -ParameterFilter { $Path -like '*.html' } -MockWith { $true }
            Mock -CommandName Test-Path -ModuleName KubeBuddy -ParameterFilter { $Path -notlike '*.html' } -MockWith { $true }
            Mock -CommandName Write-Host -ModuleName KubeBuddy -MockWith { }

            Invoke-KubeBuddy -HtmlReport -outputpath $PWD -yes

            Assert-MockCalled -CommandName Get-KubeData            -ModuleName KubeBuddy -Times 1
            Assert-MockCalled -CommandName Generate-K8sHTMLReport -ModuleName KubeBuddy -Times 1
        }

        It 'Writes an error if the HTML file was not created' {
            Mock -CommandName Test-Path -ModuleName KubeBuddy -ParameterFilter { $Path -like '*.html' } -MockWith { $false }
            Mock -CommandName Test-Path -ModuleName KubeBuddy -ParameterFilter { $Path -notlike '*.html' } -MockWith { $true }
            Mock -CommandName Write-Host -ModuleName KubeBuddy -MockWith { }
    
            Invoke-KubeBuddy -HtmlReport -OutputPath $PWD -Yes
    
            Assert-MockCalled `
                -ModuleName KubeBuddy `
                -CommandName Write-Host `
                -Times 1 `
                -ParameterFilter { $Object -like '*Failed to generate the HTML report*' }
        }    
    }

    # Context 'Text Report mode' {

    #     It 'Errors when -txtReport -Aks is missing SubscriptionId/ResourceGroup/ClusterName' {
    #         Mock -CommandName Write-Host -ModuleName KubeBuddy

    #         Invoke-KubeBuddy -txtReport -Aks -yes

    #         Assert-MockCalled -CommandName Write-Host -ModuleName KubeBuddy `
    #             -ParameterFilter { $_ -like '*-Aks requires -SubscriptionId, -ResourceGroup, and -ClusterName*' }
    #     }
    # }

    # Context 'AKS Connectivity checks' {

    #     It 'Errors if Azure CLI is not installed' {
    #         Mock -CommandName Get-Command -ModuleName KubeBuddy -MockWith { $null }
    #         Mock -CommandName Write-Host    -ModuleName KubeBuddy

    #         Invoke-KubeBuddy -Aks -SubscriptionId 'sub' -ResourceGroup 'rg' -ClusterName 'name' -yes

    #         Assert-MockCalled -CommandName Write-Host -ModuleName KubeBuddy `
    #             -ParameterFilter { $_ -like '*Azure CLI not found*' }
    #     }
    # }
}
