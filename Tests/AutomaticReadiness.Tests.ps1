$modulePath = Join-Path $PSScriptRoot '..\KubeBuddy.psm1'
Import-Module $modulePath -Force

Describe 'AKS Automatic readiness aggregation' {
    InModuleScope KubeBuddy {
        It 'marks readiness as not_ready when blockers exist' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'SEC004'
                    Name = 'Privileged Containers'
                    Severity = 'critical'
                    Category = 'Pod Security'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'privileged'
                    Total = 2
                    FailMessage = 'Privileged container found'
                    Recommendation = 'Remove privileged mode.'
                    URL = 'https://example.test/sec004'
                    Items = @(
                        [pscustomobject]@{ Resource = 'pod/ns1-a'; Issue = 'privileged=true' },
                        [pscustomobject]@{ Resource = 'pod/ns1-b'; Issue = 'privileged=true' }
                    )
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'not_ready'
            $readiness.summary.blockerCount | Should -Be 1
            $readiness.blockers.Count | Should -Be 1
            $readiness.actionPlan.Count | Should -Be 1
            $readiness.actionPlan[0].phase | Should -Be 'fix_before_migration'
        }

        It 'treats latest image tags as an AKS Automatic blocker with deny behavior' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'POD007'
                    Name = 'Container images do not use latest tag'
                    Severity = 'critical'
                    Category = 'Resource Management'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'image_tag'
                    AutomaticAdmissionBehavior = 'denies_on_enforce'
                    AutomaticMutationOutcome = 'AKS Deployment Safeguards can deny workloads that use the latest tag or omit an explicit version tag.'
                    Total = 1
                    FailMessage = 'Container image uses the latest tag'
                    Recommendation = 'Specify an explicit image tag.'
                    URL = 'https://example.test/pod007'
                    Items = @(
                        [pscustomobject]@{
                            Namespace = 'apps'
                            Resource = 'pod/web-123'
                        }
                    )
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'not_ready'
            $readiness.blockers.Count | Should -Be 1
            $readiness.blockers[0].admissionNote | Should -Match 'deny'
            $readiness.actionPlan[0].title | Should -Be 'Use explicit image tags'
        }

        It 'marks readiness as ready_with_changes when only warnings exist' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'WRK005'
                    Name = 'Missing Resource Requests or Limits'
                    Severity = 'warning'
                    Category = 'Workloads'
                    AutomaticRelevance = 'warning'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'resource_requests'
                    Total = 1
                    FailMessage = 'Missing requests'
                    Recommendation = 'Define requests.'
                    URL = 'https://example.test/wrk005'
                    Items = @([pscustomobject]@{ Resource = 'deployment/web'; Issue = 'CPU request missing' })
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'ready_with_changes'
            $readiness.summary.blockerCount | Should -Be 0
            $readiness.summary.warningCount | Should -Be 1
            $readiness.warnings.Count | Should -Be 1
        }

        It 'treats missing resource requests as an AKS Automatic blocker' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'WRK005'
                    Name = 'Missing Resource Requests or Limits'
                    Severity = 'warning'
                    Category = 'Workloads'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'resource_requests'
                    AutomaticAdmissionBehavior = 'denies_on_enforce'
                    AutomaticMutationOutcome = 'Observed on AKS Automatic: workloads with missing resource requests can be denied at admission.'
                    Total = 1
                    FailMessage = 'Missing requests'
                    Recommendation = 'Define requests.'
                    URL = 'https://example.test/wrk005'
                    Items = @([pscustomobject]@{ Resource = 'deployment/web'; Issue = 'CPU request missing' })
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'not_ready'
            $readiness.blockers[0].admissionNote | Should -Match 'deny'
        }

        It 'surfaces seccomp not configured as a warning' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'SEC020'
                    Name = 'Seccomp Profile Not Configured'
                    Severity = 'warning'
                    Category = 'Pod Security'
                    AutomaticRelevance = 'warning'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'seccomp'
                    AutomaticAdmissionBehavior = 'warns_only'
                    AutomaticMutationOutcome = 'Observed on AKS Automatic: workloads without an explicit seccomp profile can generate a warning.'
                    Total = 1
                    FailMessage = 'Seccomp profile is not configured'
                    Recommendation = 'Set seccompProfile.type to RuntimeDefault.'
                    URL = 'https://example.test/sec020'
                    Items = @([pscustomobject]@{ Resource = 'pod/web-123'; Issue = 'No explicit seccomp profile' })
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'ready_with_changes'
            $readiness.warnings[0].admissionNote | Should -Match 'warning'
        }

        It 'groups spread-constraint failures into an AKS Automatic blocker action' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'WRK015'
                    Name = 'Replicated Workloads Missing Spread Constraints'
                    Severity = 'warning'
                    Category = 'Workloads'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'pod_spread'
                    AutomaticAdmissionBehavior = 'denies_on_enforce'
                    AutomaticMutationOutcome = 'Observed on AKS Automatic: replicated workloads without pod anti-affinity or topology spread constraints can be denied at admission.'
                    Total = 1
                    FailMessage = 'Replicated workload has no pod spreading rules.'
                    Recommendation = 'Add topology spread constraints.'
                    URL = 'https://example.test/wrk015'
                    Items = @([pscustomobject]@{ Resource = 'deployment/web'; Issue = 'No spread constraints' })
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'not_ready'
            $readiness.actionPlan[0].title | Should -Be 'Add workload spreading rules'
        }

        It 'groups duplicate service selectors into an AKS Automatic blocker action' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'NET018'
                    Name = 'Duplicate Service Selectors'
                    Severity = 'warning'
                    Category = 'Networking'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'service_selector'
                    AutomaticAdmissionBehavior = 'denies_on_enforce'
                    AutomaticMutationOutcome = 'Observed on AKS Automatic: creating multiple Services with the same selector can be denied at admission.'
                    Total = 2
                    FailMessage = 'Multiple Services share the same selector'
                    Recommendation = 'Use unique selectors.'
                    URL = 'https://example.test/net018'
                    Items = @(
                        [pscustomobject]@{ Resource = 'service/web'; Issue = 'Duplicate selector' },
                        [pscustomobject]@{ Resource = 'service/web-canary'; Issue = 'Duplicate selector' }
                    )
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'not_ready'
            $readiness.actionPlan[0].title | Should -Be 'Use unique Service selectors'
        }

        It 'tracks AKS alignment separately from readiness' {
            $aksChecks = @(
                [pscustomobject]@{
                    ID = 'AKSBP015'
                    Name = 'Deployment Safeguards Enabled'
                    Severity = 'medium'
                    Category = 'Best Practices'
                    AutomaticRelevance = 'alignment'
                    AutomaticScope = 'cluster'
                    AutomaticReason = 'aks_platform'
                    Total = 1
                    FailMessage = 'Deployment safeguards disabled'
                    Recommendation = 'Enable safeguards.'
                    URL = 'https://example.test/aksbp015'
                    Items = @([pscustomobject]@{ Resource = 'cluster/aks-demo'; Issue = 'disabled' })
                }
            )

            $readiness = Get-KubeBuddyAutomaticReadiness -AksChecks $aksChecks -ClusterName 'aks-demo'

            $readiness.summary.status | Should -Be 'ready'
            $readiness.alignment.status | Should -Be 'not_aligned'
            $readiness.alignment.failed | Should -Be 1
            $readiness.actionPlan.Count | Should -Be 0
            $readiness.targetClusterBuildNotes.Count | Should -Be 1
        }

        It 'resolves pod findings to owning workload and helm metadata' {
            $yamlChecks = @(
                [pscustomobject]@{
                    ID = 'SEC004'
                    Name = 'Privileged Containers'
                    Severity = 'critical'
                    Category = 'Pod Security'
                    AutomaticRelevance = 'blocker'
                    AutomaticScope = 'workload'
                    AutomaticReason = 'privileged'
                    Total = 1
                    FailMessage = 'Privileged container found'
                    Recommendation = 'Remove privileged mode.'
                    URL = 'https://example.test/sec004'
                    Items = @(
                        [pscustomobject]@{
                            Namespace = 'apps'
                            Pod = 'web-6d4cf56db6-abcde'
                            Resource = 'pod/web-6d4cf56db6-abcde'
                        }
                    )
                }
            )

            $kubeData = [pscustomobject]@{
                Pods = [pscustomobject]@{
                    items = @(
                        [pscustomobject]@{
                            metadata = [pscustomobject]@{
                                namespace = 'apps'
                                name = 'web-6d4cf56db6-abcde'
                                ownerReferences = @(
                                    [pscustomobject]@{
                                        kind = 'ReplicaSet'
                                        name = 'web-6d4cf56db6'
                                        controller = $true
                                    }
                                )
                            }
                        }
                    )
                }
                ReplicaSets = @(
                    [pscustomobject]@{
                        metadata = [pscustomobject]@{
                            namespace = 'apps'
                            name = 'web-6d4cf56db6'
                            ownerReferences = @(
                                [pscustomobject]@{
                                    kind = 'Deployment'
                                    name = 'web'
                                    controller = $true
                                }
                            )
                        }
                    }
                )
                Deployments = @(
                    [pscustomobject]@{
                        metadata = [pscustomobject]@{
                            namespace = 'apps'
                            name = 'web'
                            labels = [pscustomobject]@{
                                'helm.sh/chart' = 'nginx-15.9.0'
                                'app.kubernetes.io/managed-by' = 'Helm'
                            }
                            annotations = [pscustomobject]@{
                                'meta.helm.sh/release-name' = 'frontend'
                                'meta.helm.sh/release-namespace' = 'apps'
                            }
                        }
                        spec = [pscustomobject]@{
                            template = [pscustomobject]@{
                                metadata = [pscustomobject]@{
                                    labels = [pscustomobject]@{}
                                    annotations = [pscustomobject]@{}
                                }
                            }
                        }
                    }
                )
            }

            $readiness = Get-KubeBuddyAutomaticReadiness -YamlChecks $yamlChecks -ClusterName 'aks-demo' -KubeData $kubeData

            $readiness.blockers[0].samples[0] | Should -Match 'Deployment/web via Pod/web-6d4cf56db6-abcde'
            $readiness.blockers[0].samples[0] | Should -Match 'Helm: release frontend, chart nginx@15.9.0'
        }

        It 'writes an action-plan HTML artifact' {
            $path = Join-Path $TestDrive 'aks-automatic-action-plan.html'
            $readiness = [pscustomobject]@{
                summary = [pscustomobject]@{
                    status = 'ready_with_changes'
                    statusLabel = 'Ready With Changes'
                    blockerCount = 0
                    warningCount = 1
                    alignmentFailedCount = 0
                }
                actionPlan = @(
                    [pscustomobject]@{
                        phase = 'fix_before_migration'
                        title = 'Define container resource requests'
                        affectedCount = 3
                        recommendations = @('Add CPU and memory requests.')
                        samples = @('deployment/web')
                    }
                )
                targetClusterBuildNotes = @(
                    [pscustomobject]@{
                        title = 'Review AKS Automatic platform defaults'
                        affectedCount = 1
                        recommendations = @('Enable deployment safeguards on the target cluster build.')
                        steps = @('Create the destination cluster with the required platform defaults.')
                        urls = @('https://example.test/aks-platform')
                        samples = @('cluster/aks-demo')
                    }
                )
            }

            New-KubeBuddyAutomaticActionPlanHtml -OutputPath $path -Readiness $readiness -ClusterName 'aks-demo'

            Test-Path $path | Should -BeTrue
            (Get-Content -Raw $path) | Should -Match 'AKS Automatic Action Plan'
            (Get-Content -Raw $path) | Should -Match 'Define container resource requests'
            (Get-Content -Raw $path) | Should -Match 'Target Cluster Build Notes'
        }

        It 'skips readiness when the AKS cluster sku is Automatic' {
            $clusterInfo = [pscustomobject]@{
                sku = [pscustomobject]@{
                    name = 'Automatic'
                }
            }

            $readiness = Get-KubeBuddyAutomaticReadiness -ClusterName 'aks-auto' -AksClusterInfo $clusterInfo

            $readiness.summary.status | Should -Be 'skipped'
            $readiness.summary.skipped | Should -BeTrue
            $readiness.actionPlan.Count | Should -Be 0
        }
    }
}
