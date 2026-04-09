Describe 'Docker entrypoint report forwarding' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'run.ps1'
        $script:runScript = Get-Content -Raw $scriptPath
    }

    It 'reads CSV_REPORT from the container environment' {
        $script:runScript | Should -Match '\$CsvReport\s*=\s*\$env:CSV_REPORT\s*-eq\s*"true"'
    }

    It 'includes CSV_REPORT in the required report-format validation' {
        $script:runScript | Should -Match 'HTML_REPORT,\s*CSV_REPORT,\s*TXT_REPORT,\s*or\s*JSON_REPORT'
    }

    It 'forwards CsvReport to Invoke-KubeBuddy' {
        $script:runScript | Should -Match 'CsvReport\s*=\s*\$CsvReport'
    }
}
