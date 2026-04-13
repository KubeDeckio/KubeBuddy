$modulePath = Join-Path $PSScriptRoot '..\KubeBuddy.psm1'
Import-Module $modulePath -Force

Describe 'Invoke-KubeBuddy wrapper' {
    BeforeEach {
        Mock -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -MockWith { 0 }
        Mock -CommandName Test-Path -ModuleName KubeBuddy -MockWith { $true }
        Mock -CommandName New-Item -ModuleName KubeBuddy -MockWith { }
        Mock -CommandName Move-KubeBuddyGeneratedReports -ModuleName KubeBuddy -MockWith { }
    }

    It 'forwards report flags to the native CLI' {
        Invoke-KubeBuddy -HtmlReport -jsonReport -CsvReport -txtReport -outputpath $PWD -yes

        Assert-MockCalled -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -Times 1 -ParameterFilter {
            $Arguments -contains 'run' -and
            $Arguments -contains '--html-report' -and
            $Arguments -contains '--json-report' -and
            $Arguments -contains '--csv-report' -and
            $Arguments -contains '--txt-report' -and
            $Arguments -contains '--yes'
        }
    }

    It 'defaults to an HTML report when no report flag is provided' {
        Invoke-KubeBuddy -outputpath $PWD

        Assert-MockCalled -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -Times 1 -ParameterFilter {
            $Arguments -contains 'run' -and
            $Arguments -contains '--html-report' -and
            -not ($Arguments -contains '--json-report') -and
            -not ($Arguments -contains '--csv-report') -and
            -not ($Arguments -contains '--txt-report')
        }
    }

    It 'maps AKS and Prometheus options to native flags' {
        Invoke-KubeBuddy `
            -HtmlReport `
            -Aks `
            -SubscriptionId 'sub' `
            -ResourceGroup 'rg' `
            -ClusterName 'cluster' `
            -ExcludeNamespaces `
            -AdditionalExcludedNamespaces 'team-a', 'team-b' `
            -IncludePrometheus `
            -PrometheusUrl 'https://example.test' `
            -PrometheusMode 'azure' `
            -PrometheusBearerTokenEnv 'PROM_TOKEN'

        Assert-MockCalled -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -Times 1 -ParameterFilter {
            $Arguments -contains '--aks' -and
            $Arguments -contains '--subscription-id' -and
            $Arguments -contains 'sub' -and
            $Arguments -contains '--resource-group' -and
            $Arguments -contains 'rg' -and
            $Arguments -contains '--cluster-name' -and
            $Arguments -contains 'cluster' -and
            $Arguments -contains '--exclude-namespaces' -and
            $Arguments -contains '--include-prometheus' -and
            $Arguments -contains '--prometheus-url' -and
            $Arguments -contains 'https://example.test' -and
            $Arguments -contains '--prometheus-mode' -and
            $Arguments -contains 'azure' -and
            $Arguments -contains '--prometheus-bearer-token-env' -and
            $Arguments -contains 'PROM_TOKEN' -and
            ($Arguments | Where-Object { $_ -eq '--additional-excluded-namespaces' }).Count -eq 2
        }
    }

    It 'maps PrometheusCredential to environment variables for basic auth' {
        $secure = ConvertTo-SecureString 'secret' -AsPlainText -Force
        $credential = [pscredential]::new('robot', $secure)

        Invoke-KubeBuddy -HtmlReport -PrometheusCredential $credential

        Assert-MockCalled -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -Times 1 -ParameterFilter {
            $Environment['PROMETHEUS_USERNAME'] -eq 'robot' -and
            $Environment['PROMETHEUS_PASSWORD'] -eq 'secret' -and
            $Arguments -contains '--prometheus-mode' -and
            $Arguments -contains 'basic'
        }
    }

    It 'renames generated reports when outputpath targets a file basename' {
        Invoke-KubeBuddy -HtmlReport -jsonReport -outputpath (Join-Path $PWD 'custom-report.html')

        Assert-MockCalled -CommandName Move-KubeBuddyGeneratedReports -ModuleName KubeBuddy -Times 1 -ParameterFilter {
            $OutputDirectory -eq $PWD.Path -and
            $BaseName -eq 'custom-report' -and
            $Extensions.Count -eq 2
        }
    }

    It 'throws when the native CLI exits with a failure code' {
        Mock -CommandName Invoke-KubeBuddyNativeCommand -ModuleName KubeBuddy -MockWith { 23 }

        {
            Invoke-KubeBuddy -HtmlReport -outputpath $PWD
        } | Should -Throw '*exited with code 23*'
    }
}
