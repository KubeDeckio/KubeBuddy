$scriptPath = Join-Path $PSScriptRoot '..\run.ps1'

Describe 'Docker entrypoint report forwarding' {
    BeforeAll {
        function global:Invoke-KubeBuddy {
            $script:capturedParams = $PSBoundParameters
            return $null
        }

        function global:chmod {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                $Arguments
            )
        }
    }

    BeforeEach {
        $script:capturedParams = $null

        $env:KUBECONFIG = '/tmp/kubeconfig'
        $env:HTML_REPORT = 'false'
        $env:CSV_REPORT = 'false'
        $env:TXT_REPORT = 'false'
        $env:JSON_REPORT = 'false'
        $env:AKS_MODE = 'false'
        $env:EXCLUDE_NAMESPACES = 'false'
        $env:USE_AKS_REST_API = 'false'
        $env:RADAR_UPLOAD = 'false'
        $env:RADAR_COMPARE = 'false'
        $env:RADAR_FETCH_CONFIG = 'false'
        $env:INCLUDE_PROMETHEUS = 'false'

        Mock Import-Module {}
        Mock Test-Path { $true }
        Mock New-Item { $null }
        Mock Copy-Item {}
        Mock Resolve-Path { '/app/Reports' }
        Mock Write-Host {}
    }

    It 'forwards HTML_REPORT to Invoke-KubeBuddy' {
        $env:HTML_REPORT = 'true'

        & $scriptPath

        $script:capturedParams | Should -Not -BeNullOrEmpty
        $script:capturedParams.HtmlReport | Should -BeTrue
    }

    It 'forwards CSV_REPORT to Invoke-KubeBuddy' {
        $env:CSV_REPORT = 'true'

        & $scriptPath

        $script:capturedParams | Should -Not -BeNullOrEmpty
        $script:capturedParams.CsvReport | Should -BeTrue
    }

    It 'forwards TXT_REPORT to Invoke-KubeBuddy' {
        $env:TXT_REPORT = 'true'

        & $scriptPath

        $script:capturedParams | Should -Not -BeNullOrEmpty
        $script:capturedParams.txtReport | Should -BeTrue
    }

    It 'forwards JSON_REPORT to Invoke-KubeBuddy' {
        $env:JSON_REPORT = 'true'

        & $scriptPath

        $script:capturedParams | Should -Not -BeNullOrEmpty
        $script:capturedParams.jsonReport | Should -BeTrue
    }
}
