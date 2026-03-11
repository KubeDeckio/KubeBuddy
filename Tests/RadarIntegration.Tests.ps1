$modulePath = Join-Path $PSScriptRoot '..\KubeBuddy.psm1'
Import-Module $modulePath -Force

Describe 'Radar integration parameters' {
    It 'Expose Radar flags on Invoke-KubeBuddy' {
        $params = (Get-Command Invoke-KubeBuddy).Parameters.Keys
        $params | Should -Contain 'RadarUpload'
        $params | Should -Contain 'RadarCompare'
        $params | Should -Contain 'RadarApiBaseUrl'
        $params | Should -Contain 'RadarFetchConfig'
        $params | Should -Contain 'RadarConfigId'
    }
}

Describe 'Radar settings resolver' {
    InModuleScope KubeBuddy {
        It 'Enables Radar when upload flag is set even if config disabled' {
            Mock Get-KubeBuddyRadarConfig {
                @{
                    enabled = $false
                    api_base_url = 'https://example.test/api'
                    environment = 'prod'
                    api_user_env = 'U'
                    api_password_env = 'P'
                    upload_timeout_seconds = 30
                    upload_retries = 1
                }
            }

            $settings = Resolve-KubeBuddyRadarSettings -RadarUpload
            $settings.enabled | Should -BeTrue
            $settings.upload_enabled | Should -BeTrue
        }
    }
}
