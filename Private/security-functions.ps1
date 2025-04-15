function Check-OrphanedSecrets {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔑 Orphaned Secrets]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Secrets..." -ForegroundColor Yellow

    $excludedSecretPatterns = @(
        "^sh\.helm\.release\.v1\.",
        "^bootstrap-token-",
        "^default-token-",
        "^kube-root-ca\.crt$"
    )

    try {
        $secrets = if ($KubeData -and $KubeData.Secrets) {
            $KubeData.Secrets
        } else {
            kubectl get secrets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to fetch secrets: $_" -ForegroundColor Red
        return
    }

    $secrets = $secrets | Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    if ($ExcludeNamespaces) {
        $secrets = Exclude-Namespaces -items $secrets
    }

    Write-Host "`r🤖 ✅ Secrets fetched. ($($secrets.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Checking Secret usage..." -ForegroundColor Yellow

    $usedSecrets = [System.Collections.Generic.HashSet[string]]::new()

    $pods = if ($KubeData -and $KubeData.Pods) { $KubeData.Pods.items } else {
        kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    $workloadTypes = @("deployments", "statefulsets", "daemonsets")
    $workloads = $workloadTypes | ForEach-Object {
        if ($KubeData -and $KubeData[$_]) { $KubeData[$_] } else {
            kubectl get $_ --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }

    $ingresses = if ($KubeData -and $KubeData.Ingresses) {
        $KubeData.Ingresses
    } else {
        kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    $serviceAccounts = if ($KubeData -and $KubeData.ServiceAccounts) {
        $KubeData.ServiceAccounts
    } else {
        kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    foreach ($resource in $pods + $workloads) {
        $resource.spec.volumes | Where-Object { $_.secret } | ForEach-Object {
            $null = $usedSecrets.Add($_.secret.secretName)
        }

        $containers = @()
        $containers += $resource.spec.containers
        $containers += $resource.spec.initContainers
        $containers += $resource.spec.ephemeralContainers

        foreach ($container in $containers) {
            $container.env | Where-Object { $_.valueFrom.secretKeyRef } | ForEach-Object {
                $null = $usedSecrets.Add($_.valueFrom.secretKeyRef.name)
            }
            $container.envFrom | Where-Object { $_.secretRef } | ForEach-Object {
                $null = $usedSecrets.Add($_.secretRef.name)
            }
        }
    }

    $ingresses | ForEach-Object {
        $_.spec.tls | Where-Object { $_.secretName } | ForEach-Object {
            $null = $usedSecrets.Add($_.secretName)
        }
    }

    $serviceAccounts | ForEach-Object {
        $_.secrets | ForEach-Object {
            $null = $usedSecrets.Add($_.name)
        }
    }

    if ($KubeData -and $KubeData.CustomResourcesByKind) {
        foreach ($kind in $KubeData.CustomResourcesByKind.Keys) {
            $resources = $KubeData.CustomResourcesByKind[$kind]
            foreach ($res in $resources) {
                if ($res.spec -and $res.spec.PSObject.Properties.name -contains "secretName") {
                    $null = $usedSecrets.Add($res.spec.secretName)
                }
            }
        }
    }

    Write-Host "`r🤖 ✅ Secret usage checked. ($($usedSecrets.Count) in use)" -ForegroundColor Green

    $orphaned = $secrets | Where-Object { -not $usedSecrets.Contains($_.metadata.name) }

    $items = foreach ($s in $orphaned) {
        $ns = if ($s.metadata.namespace) { $s.metadata.namespace } else { "N/A" }
        $name = if ($s.metadata.name) { $s.metadata.name } else { "N/A" }
    
        [PSCustomObject]@{
            Namespace = $ns
            Type      = "🔑 Secret"
            Name      = $name
        }
    }
    
    if ($items.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned Secrets found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔑 Orphaned Secrets]`n"
            Write-ToReport "✅ No orphaned Secrets found."
        }
        if ($Html) { return "<p><strong>✅ No orphaned Secrets found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    if ($Json) {
        return @{ Total = $items.Count; Items = $items }
    }

    if ($Html) {
        $htmlOutput = $items |
            ConvertTo-Html -Fragment -Property Namespace, Type, Name -PreContent "<h2>Orphaned Secrets</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Orphaned Secrets Found:</strong> $($items.Count)</p>$htmlOutput"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔑 Orphaned Secrets]`n"
        Write-ToReport "⚠️ Total Orphaned Secrets Found: $($items.Count)"
        $tableString = $items | Format-Table Namespace, Type, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $total = $items.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔑 Orphaned Secrets - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Secrets store sensitive data such as API keys and credentials.",
                "",
                "📌 This check identifies Secrets that are NOT used by:",
                "   - Pods, Deployments, StatefulSets, DaemonSets.",
                "   - Ingress TLS, ServiceAccounts, and Custom Resources.",
                "",
                "⚠️ Unused Secrets may indicate outdated credentials or misconfigurations.",
                "",
                "⚠️ Total Orphaned Secrets Found: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $items | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Type, Name -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Check-RBACOverexposure {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔓 RBAC Overexposure Check]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Analyzing Roles and Bindings..." -ForegroundColor Yellow

    $findings = @()

    try {
        $roles = if ($KubeData -and $KubeData.Roles) {
            $KubeData.Roles
        } else {
            kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $clusterRoles = if ($KubeData -and $KubeData.ClusterRoles) {
            $KubeData.ClusterRoles
        } else {
            kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $roleBindings = if ($KubeData -and $KubeData.RoleBindings) {
            $KubeData.RoleBindings
        } else {
            kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $clusterRoleBindings = if ($KubeData -and $KubeData.ClusterRoleBindings) {
            $KubeData.ClusterRoleBindings
        } else {
            kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to fetch RBAC data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $roles = Exclude-Namespaces -items $roles
        $roleBindings = Exclude-Namespaces -items $roleBindings
    }

    $wildcardRoles = @{}
    $sensitiveResourceRoles = @{}

    # Define built-in roles to identify
    $builtInClusterRoles = @(
        "cluster-admin",
        "admin",
        "edit",
        "view",
        "system:kube-scheduler",
        "system:kube-controller-manager",
        "system:node",
        "system:node-proxier",
        "system:monitoring",
        "system:service-account-issuer-discovery",
        "system:auth-delegator",
        "system:heapster",
        "system:kube-dns",
        "system:metrics-server",
        "system:public-info-viewer"
    )

    # Check 1: Wildcard Permissions
    foreach ($cr in $clusterRoles) {
        foreach ($rule in $cr.rules) {
            if ($rule.verbs -contains "*" -and $rule.resources -contains "*" -and $rule.apiGroups -contains "*") {
                $wildcardRoles[$cr.metadata.name] = "ClusterRole"
                break
            }
            # Check 2: Sensitive Resources
            $sensitiveResources = @("secrets", "pods/exec", "roles", "clusterroles", "bindings", "clusterrolebindings")
            $dangerousVerbs = @("*", "create", "update", "delete")
            if ($rule.resources | Where-Object { $_ -in $sensitiveResources }) {
                if ($rule.verbs | Where-Object { $_ -in $dangerousVerbs }) {
                    $sensitiveResourceRoles[$cr.metadata.name] = "ClusterRole"
                    break
                }
            }
        }
    }

    foreach ($r in $roles) {
        foreach ($rule in $r.rules) {
            if ($rule.verbs -contains "*" -and $rule.resources -contains "*" -and $rule.apiGroups -contains "*") {
                $key = "$($r.metadata.namespace)/$($r.metadata.name)"
                $wildcardRoles[$key] = "Role"
                break
            }
            # Check 2: Sensitive Resources
            $sensitiveResources = @("secrets", "pods/exec", "roles", "clusterroles", "bindings", "clusterrolebindings")
            $dangerousVerbs = @("*", "create", "update", "delete")
            if ($rule.resources | Where-Object { $_ -in $sensitiveResources }) {
                if ($rule.verbs | Where-Object { $_ -in $dangerousVerbs }) {
                    $key = "$($r.metadata.namespace)/$($r.metadata.name)"
                    $sensitiveResourceRoles[$key] = "Role"
                    break
                }
            }
        }
    }

    # Check 3: ClusterRoleBindings with Overexposure
    foreach ($crb in $clusterRoleBindings) {
        $roleName = $crb.roleRef.name
        $isClusterAdmin = ($roleName -eq "cluster-admin")
        $isWildcard = $wildcardRoles.ContainsKey($roleName)
        $isSensitive = $sensitiveResourceRoles.ContainsKey($roleName)

        # Check if the role is built-in
        $isBuiltIn = $false
        if ($roleName -like "system:*") {
            $isBuiltIn = $true
        }
        elseif ($roleName -in $builtInClusterRoles) {
            $isBuiltIn = $true
        }
        elseif ($clusterRoles | Where-Object { $_.metadata.name -eq $roleName -and $_.metadata.labels.'kubernetes.io/bootstrapping' -eq 'rbac-defaults' }) {
            $isBuiltIn = $true
        }

        if ($isClusterAdmin -or $isWildcard -or $isSensitive) {
            foreach ($subject in $crb.subjects) {
                # Check 4: Default ServiceAccount
                $isDefaultSA = ($subject.kind -eq "ServiceAccount" -and $subject.name -eq "default")
                $finding = [PSCustomObject]@{
                    Namespace     = "🌍 Cluster-Wide"
                    Binding       = $crb.metadata.name
                    Subject       = "$($subject.kind)/$($subject.name)"
                    Role          = $roleName
                    Scope         = "ClusterRoleBinding"
                    Risk          = if ($isClusterAdmin) { "❗ cluster-admin" } elseif ($isWildcard) { "⚠️ wildcard access" } else { "⚠️ sensitive resource access" }
                    Severity      = if ($isClusterAdmin -or $isDefaultSA) { "Critical" } else { "High" }
                    Recommendation = if ($isClusterAdmin) { "Replace with a least-privilege ClusterRole." } elseif ($isWildcard) { "Restrict the ClusterRole to specific verbs, resources, and apiGroups." } else { "Restrict access to sensitive resources like secrets or pods/exec." }
                }
                if ($isBuiltIn) {
                    $finding.Risk += " (built-in role)"
                    $finding.Recommendation += " This is a built-in Kubernetes role; proceed with caution when modifying."
                }
                if ($isDefaultSA) {
                    $finding.Risk += " (default ServiceAccount)"
                    $finding.Recommendation += " Consider using a custom ServiceAccount with limited permissions for pods."
                }
                $findings += $finding
            }
        }
    }

    # Check 5: RoleBindings with Overexposure
    foreach ($rb in $roleBindings) {
        $roleName = $rb.roleRef.name
        $ns = $rb.metadata.namespace
        $key = "$ns/$roleName"
        $isClusterAdmin = ($roleName -eq "cluster-admin")
        $isWildcard = $wildcardRoles.ContainsKey($key)
        $isSensitive = $sensitiveResourceRoles.ContainsKey($key)

        # Check if the role is built-in (for RoleBindings, this is less common, but possible if the roleRef is a ClusterRole)
        $isBuiltIn = $false
        if ($rb.roleRef.kind -eq "ClusterRole") {
            if ($roleName -like "system:*") {
                $isBuiltIn = $true
            }
            elseif ($roleName -in $builtInClusterRoles) {
                $isBuiltIn = $true
            }
            elseif ($clusterRoles | Where-Object { $_.metadata.name -eq $roleName -and $_.metadata.labels.'kubernetes.io/bootstrapping' -eq 'rbac-defaults' }) {
                $isBuiltIn = $true
            }
        }

        if ($isClusterAdmin -or $isWildcard -or $isSensitive) {
            foreach ($subject in $rb.subjects) {
                # Check 4: Default ServiceAccount
                $isDefaultSA = ($subject.kind -eq "ServiceAccount" -and $subject.name -eq "default")
                $finding = [PSCustomObject]@{
                    Namespace     = $ns
                    Binding       = $rb.metadata.name
                    Subject       = "$($subject.kind)/$($subject.name)"
                    Role          = $roleName
                    Scope         = "RoleBinding"
                    Risk          = if ($isClusterAdmin) { "❗ cluster-admin" } elseif ($isWildcard) { "⚠️ wildcard access" } else { "⚠️ sensitive resource access" }
                    Severity      = if ($isClusterAdmin -or $isDefaultSA) { "Critical" } else { "High" }
                    Recommendation = if ($isClusterAdmin) { "Replace with a least-privilege Role." } elseif ($isWildcard) { "Restrict the Role to specific verbs, resources, and apiGroups." } else { "Restrict access to sensitive resources like secrets or pods/exec." }
                }
                if ($isBuiltIn) {
                    $finding.Risk += " (built-in role)"
                    $finding.Recommendation += " This is a built-in Kubernetes role; proceed with caution when modifying."
                }
                if ($isDefaultSA) {
                    $finding.Risk += " (default ServiceAccount)"
                    $finding.Recommendation += " Consider using a custom ServiceAccount with limited permissions for pods."
                }
                $findings += $finding
            }
        }
    }

    $total = $findings.Count
    Write-Host "`r🤖 ✅ Check complete. ($total high-risk bindings found)" -ForegroundColor Green

    if ($total -eq 0) {
        Write-Host "✅ No overexposed roles or bindings found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No RBAC overexposure detected.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
            Write-ToReport "✅ No cluster-admin, wildcard, or sensitive resource access detected."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $total; Items = $findings }
    }

    if ($Html) {
        $htmlTable = $findings |
            ConvertTo-Html -Fragment -Property Namespace, Binding, Subject, Role, Scope, Risk, Severity, Recommendation -PreContent "<h2>RBAC Overexposure (cluster-admin, wildcard, or sensitive resources)</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Overexposed Bindings:</strong> $total</p>$htmlTable"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
        Write-ToReport "⚠️ Total Overexposed Bindings: $total"
        $tableString = $findings | Format-Table Namespace, Binding, Subject, Role, Scope, Risk, Severity, Recommendation -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔓 RBAC Overexposure - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 This check identifies risky access via RBAC.",
                "",
                "📌 Included:",
                "   - cluster-admin grants (direct bindings)",
                "   - Custom Roles with * verbs, * resources, * apiGroups",
                "   - Access to sensitive resources (e.g., secrets, pods/exec)",
                "   - Default ServiceAccounts with excessive permissions",
                "   - Built-in roles are flagged with a note for awareness",
                "",
                "⚠️ These bindings may allow unintended control over your cluster.",
                "",
                "⚠️ Total Overexposed Bindings Found: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $findings | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Binding, Subject, Role, Scope, Risk, Severity, Recommendation -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

# function Check-RBACMisconfigurations {
#     param(
#         [int]$PageSize = 10,
#         [switch]$Html,
#         [switch]$ExcludeNamespaces,
#         [switch]$Json,
#         [object]$KubeData
#     )

#     if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
#     Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan
#     Write-Host -NoNewline "`n🤖 Fetching RoleBindings & ClusterRoleBindings..." -ForegroundColor Yellow

#     try {
#         $roleBindings = if ($KubeData -and $KubeData.RoleBindings) {
#             $KubeData.RoleBindings
#         } else {
#             kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
#         }

#         $clusterRoleBindings = if ($KubeData -and $KubeData.ClusterRoleBindings) {
#             $KubeData.ClusterRoleBindings
#         } else {
#             kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
#         }

#         $roles = if ($KubeData -and $KubeData.Roles) {
#             $KubeData.Roles
#         } else {
#             kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
#         }

#         $clusterRoles = if ($KubeData -and $KubeData.ClusterRoles) {
#             $KubeData.ClusterRoles
#         } else {
#             kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
#         }

#         $existingNamespaces = if ($KubeData -and $KubeData.Namespaces) {
#             $KubeData.Namespaces | ForEach-Object { $_.metadata.name }
#         } else {
#             kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | ForEach-Object { $_.metadata.name }
#         }

#         $serviceAccounts = if ($KubeData -and $KubeData.ServiceAccounts) {
#             $KubeData.ServiceAccounts
#         } else {
#             kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
#         }
#     }
#     catch {
#         Write-Host "`r🤖 ❌ Error retrieving RBAC data: $_" -ForegroundColor Red
#         return
#     }

#     if ($ExcludeNamespaces) {
#         $roleBindings = Exclude-Namespaces -items $roleBindings
#         $roles = Exclude-Namespaces -items $roles
#         $serviceAccounts = Exclude-Namespaces -items $serviceAccounts
#     }

#     Write-Host "`r🤖 ✅ Fetched $($roleBindings.Count) RoleBindings, $($clusterRoleBindings.Count) ClusterRoleBindings, $($roles.Count) Roles, $($clusterRoles.Count) ClusterRoles, $($serviceAccounts.Count) ServiceAccounts.`n" -ForegroundColor Green
#     Write-Host -NoNewline "🤖 Analyzing RBAC configurations..." -ForegroundColor Yellow

#     $invalidRBAC = @()

#     # Check 1: Missing RoleRef in Bindings
#     foreach ($rb in $roleBindings) {
#         if (-not $rb.roleRef) {
#             $invalidRBAC += [PSCustomObject]@{
#                 Namespace     = $rb.metadata.namespace
#                 Type          = "🔹 Namespace Role"
#                 RoleBinding   = $rb.metadata.name
#                 Subject       = "N/A"
#                 Issue         = "🚩 Missing roleRef in RoleBinding"
#                 Severity      = "High"
#                 Recommendation = "Delete the RoleBinding or specify a valid roleRef."
#             }
#             continue
#         }

#         $rbNamespace = $rb.metadata.namespace
#         $namespaceExists = $rbNamespace -in $existingNamespaces

#         # Check 2: Missing Role for RoleBinding
#         $roleExists = $roles | Where-Object {
#             $_.metadata.name -eq $rb.roleRef.name -and $_.metadata.namespace -eq $rbNamespace
#         }

#         if (-not $roleExists -and $rb.roleRef.kind -eq "Role") {
#             $invalidRBAC += [PSCustomObject]@{
#                 Namespace     = if ($namespaceExists) { $rbNamespace } else { "🚩 Namespace Missing" }
#                 Type          = "🔹 Namespace Role"
#                 RoleBinding   = $rb.metadata.name
#                 Subject       = "N/A"
#                 Issue         = "❌ Missing Role: $($rb.roleRef.name)"
#                 Severity      = "High"
#                 Recommendation = "Create the missing Role or update the RoleBinding to reference an existing Role."
#             }
#         }

#         # Check 3: RoleBinding Referencing ClusterRole
#         if ($rb.roleRef.kind -eq "ClusterRole") {
#             $clusterRole = $clusterRoles | Where-Object { $_.metadata.name -eq $rb.roleRef.name }
#             if ($clusterRole) {
#                 $invalidRBAC += [PSCustomObject]@{
#                     Namespace     = $rbNamespace
#                     Type          = "🔹 Namespace Role"
#                     RoleBinding   = $rb.metadata.name
#                     Subject       = if ($rb.subjects) { ($rb.subjects | ForEach-Object { "$($_.kind)/$($_.name)" }) -join ", " } else { "N/A" }
#                     Issue         = "⚠️ RoleBinding references ClusterRole: $($rb.roleRef.name)"
#                     Severity      = "Medium"
#                     Recommendation = "Consider using a namespace-scoped Role instead of a ClusterRole to limit permissions to the namespace."
#                 }
#             }
#         }

#         # Check 4: Missing ServiceAccounts and Namespaces
#         foreach ($subject in $rb.subjects) {
#             if ($subject.kind -eq "ServiceAccount") {
#                 $subjectNamespace = if ($subject.namespace) { $subject.namespace } else { $rbNamespace }
#                 if (-not $namespaceExists) {
#                     $invalidRBAC += [PSCustomObject]@{
#                         Namespace     = "🚩 Namespace Missing"
#                         Type          = "🔹 Namespace Role"
#                         RoleBinding   = $rb.metadata.name
#                         Subject       = "$($subject.kind)/$($subject.name)"
#                         Issue         = "🚩 Namespace does not exist"
#                         Severity      = "High"
#                         Recommendation = "Delete the RoleBinding or update the namespace to an existing one."
#                     }
#                 } else {
#                     $exists = $serviceAccounts | Where-Object {
#                         $_.metadata.name -eq $subject.name -and $_.metadata.namespace -eq $subjectNamespace
#                     }
#                     if (-not $exists) {
#                         $invalidRBAC += [PSCustomObject]@{
#                             Namespace     = $rbNamespace
#                             Type          = "🔹 Namespace Role"
#                             RoleBinding   = $rb.metadata.name
#                             Subject       = "$($subject.kind)/$($subject.name)"
#                             Issue         = "❌ ServiceAccount does not exist in namespace $subjectNamespace"
#                             Severity      = "High"
#                             Recommendation = "Create the missing ServiceAccount or update the RoleBinding to reference an existing ServiceAccount."
#                         }
#                     }
#                 }
#             }
#         }
#     }

#     foreach ($crb in $clusterRoleBindings) {
#         # Check 5: Missing RoleRef in ClusterRoleBinding
#         if (-not $crb.roleRef) {
#             $invalidRBAC += [PSCustomObject]@{
#                 Namespace     = "🌍 Cluster-Wide"
#                 Type          = "🔸 Cluster Role"
#                 RoleBinding   = $crb.metadata.name
#                 Subject       = "N/A"
#                 Issue         = "🚩 Missing roleRef in ClusterRoleBinding"
#                 Severity      = "High"
#                 Recommendation = "Delete the ClusterRoleBinding or specify a valid roleRef."
#             }
#             continue
#         }

#         # Check 6: Missing ServiceAccounts and Namespaces in ClusterRoleBindings
#         foreach ($subject in $crb.subjects) {
#             if ($subject.kind -eq "ServiceAccount") {
#                 $subjectNamespace = $subject.namespace
#                 if (-not $subjectNamespace) {
#                     $invalidRBAC += [PSCustomObject]@{
#                         Namespace     = "🌍 Cluster-Wide"
#                         Type          = "🔸 Cluster Role"
#                         RoleBinding   = $crb.metadata.name
#                         Subject       = "$($subject.kind)/$($subject.name)"
#                         Issue         = "🚩 Namespace not specified for ServiceAccount"
#                         Severity      = "High"
#                         Recommendation = "Specify a valid namespace for the ServiceAccount in the ClusterRoleBinding."
#                     }
#                 }
#                 elseif ($subjectNamespace -notin $existingNamespaces) {
#                     $invalidRBAC += [PSCustomObject]@{
#                         Namespace     = "🚩 Namespace Missing"
#                         Type          = "🔸 Cluster Role"
#                         RoleBinding   = $crb.metadata.name
#                         Subject       = "$($subject.kind)/$($subject.name)"
#                         Issue         = "🚩 Namespace does not exist: $subjectNamespace"
#                         Severity      = "High"
#                         Recommendation = "Delete the ClusterRoleBinding or update the namespace to an existing one."
#                     }
#                 } else {
#                     $exists = $serviceAccounts | Where-Object {
#                         $_.metadata.name -eq $subject.name -and $_.metadata.namespace -eq $subjectNamespace
#                     }
#                     if (-not $exists) {
#                         $invalidRBAC += [PSCustomObject]@{
#                             Namespace     = "🌍 Cluster-Wide"
#                             Type          = "🔸 Cluster Role"
#                             RoleBinding   = $crb.metadata.name
#                             Subject       = "$($subject.kind)/$($subject.name)"
#                             Issue         = "❌ ServiceAccount does not exist in namespace $subjectNamespace"
#                             Severity      = "High"
#                             Recommendation = "Create the missing ServiceAccount or update the ClusterRoleBinding to reference an existing ServiceAccount."
#                         }
#                     }
#                 }
#             }
#         }
#     }

#     Write-Host "`r🤖 ✅ RBAC configurations Checked.       " -ForegroundColor Green

#     if ($invalidRBAC.Count -eq 0) {
#         Write-Host "`r✅ No RBAC misconfigurations found." -ForegroundColor Green
#         if ($Html) { return "<p><strong>✅ No RBAC misconfigurations found.</strong></p>" }
#         if ($Json) { return @{ Total = 0; Items = @() } }
#         if ($Global:MakeReport -and -not $Html) {
#             Write-ToReport "`n[RBAC Misconfigurations]`n"
#             Write-ToReport "✅ No RBAC misconfigurations found."
#         }
#         if (-not $Global:MakeReport -and -not $Html) {
#             Read-Host "🤖 Press Enter to return to the menu"
#         }
#         return
#     }

#     if ($Json) {
#         return @{ Total = $invalidRBAC.Count; Items = $invalidRBAC }
#     }

#     if ($Html) {
#         $htmlTable = $invalidRBAC |
#             ConvertTo-Html -Fragment -Property Namespace, Type, RoleBinding, Subject, Issue, Severity, Recommendation -PreContent "<h2>RBAC Misconfigurations</h2>" |
#             Out-String
#         return "<p><strong>⚠️ Total RBAC Misconfigurations Detected:</strong> $($invalidRBAC.Count)</p>$htmlTable"
#     }

#     if ($Global:MakeReport) {
#         Write-ToReport "`n[RBAC Misconfigurations]`n"
#         Write-ToReport "⚠️ Total RBAC Misconfigurations Detected: $($invalidRBAC.Count)"
#         $tableString = $invalidRBAC | Format-Table Namespace, Type, RoleBinding, Subject, Issue, Severity, Recommendation -AutoSize | Out-String
#         Write-ToReport $tableString
#         return
#     }

#     $total = $invalidRBAC.Count
#     $currentPage = 0
#     $totalPages = [math]::Ceiling($total / $PageSize)

#     do {
#         Clear-Host
#         Write-Host "`n[RBAC Misconfigurations - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

#         if ($currentPage -eq 0) {
#             $msg = @(
#                 "🤖 RBAC (Role-Based Access Control) defines who can do what in your cluster.",
#                 "",
#                 "📌 This check identifies:",
#                 "   - 🔍 Misconfigurations in RoleBindings & ClusterRoleBindings.",
#                 "   - ❌ Missing references to ServiceAccounts & Namespaces.",
#                 "   - ⚠️ RoleBindings referencing ClusterRoles.",
#                 "",
#                 "⚠️ Total RBAC Misconfigurations Detected: $total"
#             )
#             Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
#         }

#         $paged = $invalidRBAC | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
#         $paged | Format-Table Namespace, Type, RoleBinding, Subject, Issue, Severity, Recommendation -AutoSize | Out-Host

#         $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
#         if ($newPage -eq -1) { break }
#         $currentPage = $newPage

#     } while ($true)
# }

function Check-HostPidAndNetwork {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔌 Pods with hostPID / hostNetwork]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    try {
        $pods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($($pods.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Scanning for hostPID / hostNetwork usage..." -ForegroundColor Yellow

    $flaggedPods = foreach ($pod in $pods) {
        $hostPID = $pod.spec.hostPID
        $hostNetwork = $pod.spec.hostNetwork

        if ($hostPID -or $hostNetwork) {
            [PSCustomObject]@{
                Namespace   = $pod.metadata.namespace
                Pod         = $pod.metadata.name
                hostPID     = if ($hostPID -eq $true) { "❌ true" } else { "✅ false" }
                hostNetwork = if ($hostNetwork -eq $true) { "❌ true" } else { "✅ false" }
            }
        }
    }

    Write-Host "`r🤖 ✅ Scan complete. ($($flaggedPods.Count) flagged)              " -ForegroundColor Green

    if ($flaggedPods.Count -eq 0) {
        Write-Host "✅ No pods with hostPID or hostNetwork found." -ForegroundColor Green
        if ($Html) {
            return "<p><strong>✅ No pods with hostPID or hostNetwork found.</strong></p>"
        }
        if ($Json) {
            return @{ Total = 0; Items = @() }
        }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔌 Pods with hostPID / hostNetwork]`n"
            Write-ToReport "✅ No pods with hostPID or hostNetwork found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $flaggedPods.Count; Items = $flaggedPods }
    }

    if ($Html) {
        $htmlTable = $flaggedPods |
            ConvertTo-Html -Fragment -Property Namespace, Pod, hostPID, hostNetwork -PreContent "<h2>Pods with hostPID / hostNetwork</h2>" |
            Out-String

        return "<p><strong>⚠️ Total Flagged Pods:</strong> $($flaggedPods.Count)</p>$htmlTable"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔌 Pods with hostPID / hostNetwork]`n"
        Write-ToReport "⚠️ Total Flagged Pods: $($flaggedPods.Count)"
        $tableString = $flaggedPods | Format-Table Namespace, Pod, hostPID, hostNetwork -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $totalItems = $flaggedPods.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔌 Pods with hostPID / hostNetwork - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Some pods use host-level process or network namespaces.",
                "",
                "📌 This check identifies pods with:",
                "   - hostPID = true",
                "   - hostNetwork = true",
                "",
                "⚠️ These settings can bypass isolation and expose the node.",
                "",
                "⚠️ Total Flagged Pods: $($flaggedPods.Count)"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)
        $flaggedPods[$startIndex..($endIndex - 1)] | Format-Table Namespace, Pod, hostPID, hostNetwork -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PodsRunningAsRoot {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[👑 Pods Running as Root]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    try {
        $pods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($($pods.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Scanning for root user usage..." -ForegroundColor Yellow

    $rootPods = @()

    foreach ($pod in $pods) {
        $podUser = $pod.spec.securityContext.runAsUser

        foreach ($container in $pod.spec.containers) {
            $containerUser = $container.securityContext.runAsUser
            $isRoot = -not $containerUser -and -not $podUser

            if (($containerUser -eq 0) -or ($podUser -eq 0) -or $isRoot) {
                $rootPods += [PSCustomObject]@{
                    Namespace = $pod.metadata.namespace
                    Pod       = $pod.metadata.name
                    Container = $container.name
                    runAsUser = if ($containerUser) {
                        $containerUser
                    } elseif ($podUser) {
                        $podUser
                    } else {
                        "Not Set (Defaults to root)"
                    }
                }
            }
        }
    }

    Write-Host "`r🤖 ✅ Scan complete. ($($rootPods.Count) flagged)   " -ForegroundColor Green

    if ($rootPods.Count -eq 0) {
        Write-Host "✅ No pods running as root." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[👑 Pods Running as Root]`n"
            Write-ToReport "✅ No pods running as root."
        }
        if ($Html) { return "<p><strong>✅ No pods running as root.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        $htmlTable = $rootPods |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Container, runAsUser -PreContent "<h2>Pods Running as Root</h2>" |
            Out-String

        return "<p><strong>⚠️ Total Pods Running as Root:</strong> $($rootPods.Count)</p>$htmlTable"
    }

    if ($Json) {
        return @{ Total = $rootPods.Count; Items = $rootPods }
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[👑 Pods Running as Root]`n"
        Write-ToReport "⚠️ Total Pods Running as Root: $($rootPods.Count)"
        $tableString =$rootPods | Format-Table Namespace, Pod, Container, runAsUser -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $totalItems = $rootPods.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[👑 Pods Running as Root - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Some pods are running as root (UID 0) or without explicit user settings.",
                "",
                "📌 This check looks for:",
                "   - container or pod runAsUser = 0",
                "   - runAsUser not set (defaults to root)",
                "",
                "⚠️ Running as root bypasses container security boundaries.",
                "",
                "⚠️ Total Flagged Pods: $($rootPods.Count)"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $rootPods[$startIndex..($endIndex - 1)] |
            Format-Table Namespace, Pod, Container, runAsUser -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PrivilegedContainers {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔓 Privileged Containers]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    try {
        $pods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($($pods.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Scanning for privileged containers..." -ForegroundColor Yellow

    $privileged = @()

    foreach ($pod in $pods) {
        foreach ($container in $pod.spec.containers) {
            if ($container.securityContext.privileged -eq $true) {
                $privileged += [PSCustomObject]@{
                    Namespace = $pod.metadata.namespace
                    Pod       = $pod.metadata.name
                    Container = $container.name
                }
            }
        }
    }

    Write-Host "`r🤖 ✅ Scan complete. ($($privileged.Count) flagged)        " -ForegroundColor Green

    if ($privileged.Count -eq 0) {
        Write-Host "✅ No privileged containers found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔓 Privileged Containers]`n"
            Write-ToReport "✅ No privileged containers found."
        }
        if ($Html) { return "<p><strong>✅ No privileged containers found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        $htmlTable = $privileged |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Container -PreContent "<h2>Privileged Containers</h2>" |
            Out-String

        return "<p><strong>⚠️ Total Privileged Containers Found:</strong> $($privileged.Count)</p>$htmlTable"
    }

    if ($Json) {
        return @{ Total = $privileged.Count; Items = $privileged }
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔓 Privileged Containers]`n"
        Write-ToReport "⚠️ Total Privileged Containers Found: $($privileged.Count)"
        $tableString = $privileged | Format-Table Namespace, Pod, Container -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $totalItems = $privileged.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔓 Privileged Containers - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Privileged containers run with extended access to the host.",
                "",
                "📌 This check flags containers where:",
                "   - securityContext.privileged = true",
                "",
                "⚠️ This setting grants broad capabilities and should be avoided.",
                "",
                "⚠️ Total Privileged Containers Found: $($privileged.Count)"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $privileged[$startIndex..($endIndex - 1)] |
            Format-Table Namespace, Pod, Container -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-OrphanedServiceAccounts {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🧾 Orphaned ServiceAccounts]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching ServiceAccount data..." -ForegroundColor Yellow

    try {
        $sas = if ($KubeData -and $KubeData.ServiceAccounts) {
            $KubeData.ServiceAccounts
        } else {
            kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $roleBindings = if ($KubeData -and $KubeData.RoleBindings) {
            $KubeData.RoleBindings
        } else {
            kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $clusterRoleBindings = if ($KubeData -and $KubeData.ClusterRoleBindings) {
            $KubeData.ClusterRoleBindings
        } else {
            kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }

        $pods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch RBAC or Pod data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $excludedSet = (Get-ExcludedNamespaces) | ForEach-Object { $_.ToLowerInvariant() }
    
        $sas = $sas | Where-Object { $_.metadata.namespace.ToLowerInvariant() -notin $excludedSet }
        $roleBindings = $roleBindings | Where-Object { $_.metadata.namespace.ToLowerInvariant() -notin $excludedSet }
        $pods = $pods | Where-Object { $_.metadata.namespace.ToLowerInvariant() -notin $excludedSet }
        $clusterRoleBindings = $clusterRoleBindings | Where-Object {
            $_.subjects | Where-Object {
                $_.kind -eq "ServiceAccount" -and $_.namespace -and ($_.namespace.ToLowerInvariant() -notin $excludedSet)
            }
        }
    }    

    Write-Host "`r🤖 ✅ Resources fetched. Analyzing usage..." -ForegroundColor Green

    $usedSAs = [System.Collections.Generic.HashSet[string]]::new()

    # Pods using SAs
    foreach ($pod in $pods) {
        $sa = $pod.spec.serviceAccountName
        if ($sa) {
            $null = $usedSAs.Add("$($pod.metadata.namespace)/$sa")
        }
    }

    # RoleBindings referencing SAs
    foreach ($rb in $roleBindings) {
        foreach ($s in $rb.subjects) {
            if ($s.kind -eq "ServiceAccount" -and $s.name) {
                $ns = if ($s.namespace) { $s.namespace } else { $rb.metadata.namespace }
                $null = $usedSAs.Add("$ns/$($s.name)")
            }
        }
    }

    # ClusterRoleBindings referencing SAs
    foreach ($crb in $clusterRoleBindings) {
        foreach ($s in $crb.subjects) {
            if ($s.kind -eq "ServiceAccount" -and $s.namespace -and $s.name) {
                $null = $usedSAs.Add("$($s.namespace)/$($s.name)")
            }
        }
    }

    # Find unused SAs
    $orphaned = $sas | Where-Object {
        -not $usedSAs.Contains("$($_.metadata.namespace)/$($_.metadata.name)")
    }

    $items = foreach ($sa in $orphaned) {
        [PSCustomObject]@{
            Namespace = $sa.metadata.namespace
            Name      = $sa.metadata.name
        }
    }

    $total = $items.Count
    if ($total -eq 0) {
        Write-Host "`r🤖 ✅ No orphaned ServiceAccounts found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No orphaned ServiceAccounts found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🧾 Orphaned ServiceAccounts]`n✅ None found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Orphaned ServiceAccounts found: $total" -ForegroundColor Green

    if ($Json) {
        return @{ Total = $total; Items = $items }
    }

    if ($Html) {
        $htmlOutput = $items |
            ConvertTo-Html -Fragment -Property Namespace, Name |
            Out-String
        return "<p><strong>⚠️ Orphaned ServiceAccounts:</strong> $total</p>" + $htmlOutput
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🧾 Orphaned ServiceAccounts]`n⚠️ Total: $total"
        $tableString = $items | Format-Table Namespace, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🧾 Orphaned ServiceAccounts - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 These ServiceAccounts aren't used in RoleBindings, ClusterRoleBindings, or Pods.",
                "",
                "📌 Why this matters:",
                "   - Unused SAs might be leftover from old workloads.",
                "   - Could indicate stale or misconfigured access paths.",
                "",
                "⚠️ Total: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $items | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Name -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-OrphanedRoles {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🗂️ Unused Roles & ClusterRoles]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching RBAC data..." -ForegroundColor Yellow

    try {
        $roles = if ($KubeData -and $KubeData.Roles) { $KubeData.Roles } else { kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items }
        $clusterRoles = if ($KubeData -and $KubeData.ClusterRoles) { $KubeData.ClusterRoles } else { kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items }
        $roleBindings = if ($KubeData -and $KubeData.RoleBindings) { $KubeData.RoleBindings } else { kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items }
        $clusterRoleBindings = if ($KubeData -and $KubeData.ClusterRoleBindings) { $KubeData.ClusterRoleBindings } else { kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items }
    }
    catch {
        Write-Host "`r🤖 ❌ Error fetching RBAC data: $_" -ForegroundColor Red
        return
    }

    $usedRoleNames = [System.Collections.Generic.HashSet[string]]::new()
    $usedClusterRoleNames = [System.Collections.Generic.HashSet[string]]::new()

    $results = @()

    # Check 1: Bindings with No Subjects
    foreach ($rb in $roleBindings) {
        if (-not $rb.subjects -or $rb.subjects.Count -eq 0) {
            $results += [PSCustomObject]@{
                Namespace     = $rb.metadata.namespace
                Role          = $rb.roleRef.name
                Type          = "RoleBinding"
                Issue         = "🚩 No subjects defined"
                Severity      = "Low"
                Recommendation = "Delete the RoleBinding as it has no effect."
            }
        }
        if ($rb.roleRef.kind -eq "Role") {
            $usedRoleNames.Add("$($rb.metadata.namespace)/$($rb.roleRef.name)") | Out-Null
        }
        elseif ($rb.roleRef.kind -eq "ClusterRole") {
            $usedClusterRoleNames.Add($rb.roleRef.name) | Out-Null
        }
    }

    foreach ($crb in $clusterRoleBindings) {
        if (-not $crb.subjects -or $crb.subjects.Count -eq 0) {
            $results += [PSCustomObject]@{
                Namespace     = "🌍 Cluster-Wide"
                Role          = $crb.roleRef.name
                Type          = "ClusterRoleBinding"
                Issue         = "🚩 No subjects defined"
                Severity      = "Low"
                Recommendation = "Delete the ClusterRoleBinding as it has no effect."
            }
        }
        if ($crb.roleRef.kind -eq "ClusterRole") {
            $usedClusterRoleNames.Add($crb.roleRef.name) | Out-Null
        }
    }

    # Define built-in roles to exclude
    $builtInClusterRoles = @(
        "cluster-admin",
        "admin",
        "edit",
        "view",
        "system:kube-scheduler",
        "system:kube-controller-manager",
        "system:node",
        "system:node-proxier",
        "system:monitoring",
        "system:service-account-issuer-discovery",
        "system:auth-delegator",
        "system:heapster",
        "system:kube-dns",
        "system:metrics-server",
        "system:public-info-viewer"
    )

    # Filter Roles by excluded namespaces, if applicable
    if ($ExcludeNamespaces) {
        $excludedSet = (Get-ExcludedNamespaces) | ForEach-Object { $_.ToLowerInvariant() }
        Write-Host "`n🤖 Excluding namespaces for Roles: $($excludedSet -join ', ')" -ForegroundColor Yellow
        $roles = $roles | Where-Object { $_.metadata.namespace.ToLowerInvariant() -notin $excludedSet }
    }

    # Check 2: Unused Roles
    foreach ($r in $roles) {
        $key = "$($r.metadata.namespace)/$($r.metadata.name)"
        if (-not $usedRoleNames.Contains($key)) {
            $results += [PSCustomObject]@{
                Namespace     = $r.metadata.namespace
                Role          = $r.metadata.name
                Type          = "Role"
                Issue         = "⚠️ Unused Role"
                Severity      = "Low"
                Recommendation = "Delete the unused Role to reduce clutter."
            }
        }
        # Check 3: Roles with No Rules (Zero-Effect)
        if (-not $r.rules -or $r.rules.Count -eq 0) {
            $results += [PSCustomObject]@{
                Namespace     = $r.metadata.namespace
                Role          = $r.metadata.name
                Type          = "Role"
                Issue         = "🚩 No rules defined"
                Severity      = "Low"
                Recommendation = "Delete the Role or define rules to make it effective."
            }
        }
    }

    # Check 4: Unused ClusterRoles, excluding built-in roles
    foreach ($cr in $clusterRoles) {
        $isBuiltIn = $false
        # Check for system: prefix
        if ($cr.metadata.name -like "system:*") {
            $isBuiltIn = $true
        }
        # Check for well-known built-in roles
        elseif ($cr.metadata.name -in $builtInClusterRoles) {
            $isBuiltIn = $true
        }
        # Check for kubernetes.io/bootstrapping label
        elseif ($cr.metadata.labels -and $cr.metadata.labels.'kubernetes.io/bootstrapping' -eq 'rbac-defaults') {
            $isBuiltIn = $true
        }

        if (-not $isBuiltIn -and -not $usedClusterRoleNames.Contains($cr.metadata.name)) {
            $results += [PSCustomObject]@{
                Namespace     = "🌍 Cluster-Wide"
                Role          = $cr.metadata.name
                Type          = "ClusterRole"
                Issue         = "⚠️ Unused ClusterRole"
                Severity      = "Low"
                Recommendation = "Delete the unused ClusterRole to reduce clutter."
            }
        }
        # Check 5: ClusterRoles with No Rules (Zero-Effect)
        if (-not $cr.rules -or $cr.rules.Count -eq 0) {
            $results += [PSCustomObject]@{
                Namespace     = "🌍 Cluster-Wide"
                Role          = $cr.metadata.name
                Type          = "ClusterRole"
                Issue         = "🚩 No rules defined"
                Severity      = "Low"
                Recommendation = "Delete the ClusterRole or define rules to make it effective."
            }
        }
    }

    $total = $results.Count
    Write-Host "`r🤖 ✅ RBAC analysis complete. ($total unused or ineffective roles/bindings found)" -ForegroundColor Green

    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ No unused or ineffective roles/bindings found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) { Write-ToReport "`n[🗂️ Unused Roles & ClusterRoles]`n✅ No unused or ineffective roles/bindings." }
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    if ($Json) { return @{ Total = $total; Items = $results } }
    if ($Html) {
        $htmlOutput = $results | ConvertTo-Html -Fragment -Property Namespace, Role, Type, Issue, Severity, Recommendation | Out-String
        return "<p><strong>⚠️ Unused or Ineffective Roles/Bindings:</strong> $total</p>" + $htmlOutput
    }
    if ($Global:MakeReport) {
        Write-ToReport "`n[🗂️ Unused Roles & ClusterRoles]`n⚠️ Total: $total"
        $tableString = $results | Format-Table Namespace, Role, Type, Issue, Severity, Recommendation -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[🗂️ Unused Roles - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 These Roles, ClusterRoles, and Bindings are unused or ineffective.",
                "",
                "📌 Why this matters:",
                "   - Unused roles/bindings add clutter and confusion.",
                "   - May be leftovers from uninstalled apps.",
                "   - Bindings with no subjects or roles with no rules have no effect.",
                "   - Built-in Kubernetes roles (e.g., system:*, cluster-admin) are excluded.",
                "",
                "⚠️ Total unused or ineffective roles/bindings: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }
        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Role, Type, Issue, Severity, Recommendation -AutoSize | Out-Host
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}