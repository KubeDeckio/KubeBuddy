function Check-OrphanedConfigMaps {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📜 Orphaned ConfigMaps]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow

    # Exclude Helm-managed ConfigMaps
    $excludedConfigMapPatterns = @("^sh\.helm\.release\.v1\.")

    $configMaps = kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch ($excludedConfigMapPatterns -join "|") }

    if ($ExcludeNamespaces) {
        $configMaps = Exclude-Namespaces -items $configMaps
    }    

    Write-Host "`r🤖 ✅ ConfigMaps fetched. ($($configMaps.Count) total)" -ForegroundColor Green

    # Fetch workloads & used ConfigMaps
    Write-Host -NoNewline "`n🤖 Checking ConfigMap usage..." -ForegroundColor Yellow
    $usedConfigMaps = @()

    # Pods
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Various workloads
    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get cronjobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get jobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get replicasets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Scan Pods + workloads for configmap references
    foreach ($resource in $pods + $workloads) {
        $usedConfigMaps += $resource.spec.volumes | Where-Object { $_.configMap } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name

        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedConfigMaps += $container.env | Where-Object { $_.valueFrom.configMapKeyRef } |
                Select-Object -ExpandProperty valueFrom |
                Select-Object -ExpandProperty configMapKeyRef |
                Select-Object -ExpandProperty name
            }
            if ($container.envFrom) {
                $usedConfigMaps += $container.envFrom | Where-Object { $_.configMapRef } |
                Select-Object -ExpandProperty configMapRef |
                Select-Object -ExpandProperty name
            }
        }
    }

    # Ingress & Service annotations
    $usedConfigMaps += $ingresses | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }
    $usedConfigMaps += $services  | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }

    # Custom Resources
    $crds = kubectl get crds -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    foreach ($crd in $crds) {
        $crdKind = $crd.spec.names.kind
        if ($crdKind -match "^[a-z0-9-]+$") {
            $customResources = kubectl get $crdKind --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
            foreach ($cr in $customResources) {
                if ($cr.metadata.annotations.Values -match "configMap") {
                    $usedConfigMaps += $cr.metadata.annotations.Values
                }
            }
        }
    }

    # Clean up references
    $usedConfigMaps = $usedConfigMaps | Where-Object { $_ } | Sort-Object -Unique
    Write-Host "`r✅ ConfigMap usage checked.   " -ForegroundColor Green

    # Orphaned = not in usedConfigMaps
    $orphanedConfigMaps = $configMaps | Where-Object { $_.metadata.name -notin $usedConfigMaps }

    # Build an array for pagination / output
    $orphanedItems = @()
    foreach ($ocm in $orphanedConfigMaps) {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $ocm.metadata.namespace
            Type      = "📜 ConfigMap"
            Name      = $ocm.metadata.name
        }
    }

    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned ConfigMaps found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
            Write-ToReport "✅ No orphaned ConfigMaps found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html is specified, create & return an HTML table
    if ($Html) {
        $htmlTable = $orphanedItems |
        ConvertTo-Html -Fragment -Property Namespace, Type, Name -PreContent "<h2>Orphaned ConfigMaps</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Orphaned ConfigMaps Found:</strong> $($orphanedItems.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode, ASCII
    if ($Global:MakeReport) {
        Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
        Write-ToReport "⚠️ Total Orphaned ConfigMaps Found: $($orphanedItems.Count)"

        $tableString = $orphanedItems | Format-Table Namespace, Type, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems = $orphanedItems.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📜 Orphaned ConfigMaps - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 ConfigMaps store configuration data for workloads.",
            "",
            "📌 This check identifies ConfigMaps that are not referenced by:",
            "   - Pods, Deployments, StatefulSets, DaemonSets.",
            "   - CronJobs, Jobs, ReplicaSets, Services, and Custom Resources.",
            "",
            "⚠️ Orphaned ConfigMaps may be outdated and can be reviewed for cleanup.",
            "",
            "⚠️ Total Orphaned ConfigMaps Found: $($orphanedItems.Count)"
        )
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, Name -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-OrphanedSecrets {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔑 Orphaned Secrets]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Secrets..." -ForegroundColor Yellow

    # Exclude system-managed secrets
    $excludedSecretPatterns = @("^sh\.helm\.release\.v1\.", "^bootstrap-token-", "^default-token-", "^kube-root-ca.crt$", "^kubernetes.io/service-account-token")

    $secrets = kubectl get secrets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    if ($ExcludeNamespaces) {
        $secrets = Exclude-Namespaces -items $secrets
    }

    Write-Host "`r🤖 ✅ Secrets fetched. ($($secrets.Count) total)" -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Checking Secret usage..." -ForegroundColor Yellow
    $usedSecrets = @()

    # Pods and various workloads
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $serviceAccounts = kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    foreach ($resource in $pods + $workloads) {
        $usedSecrets += $resource.spec.volumes | Where-Object { $_.secret } |
        Select-Object -ExpandProperty secret |
        Select-Object -ExpandProperty secretName

        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedSecrets += $container.env | Where-Object { $_.valueFrom.secretKeyRef } |
                Select-Object -ExpandProperty valueFrom |
                Select-Object -ExpandProperty secretKeyRef |
                Select-Object -ExpandProperty name
            }
        }
    }

    # Ingress TLS
    $usedSecrets += $ingresses | ForEach-Object {
        if ($_.spec.tls) {
            $_.spec.tls | Where-Object { $_.secretName } | Select-Object -ExpandProperty secretName
        }
    }    
    # ServiceAccounts
    $usedSecrets += $serviceAccounts | ForEach-Object { $_.secrets | Select-Object -ExpandProperty name }

    # Check custom resources
    $customResources = kubectl api-resources --verbs=list --namespaced -o name | Where-Object { $_ }
    foreach ($cr in $customResources) {
        $crInstances = kubectl get $cr --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
        if ($crInstances) {
            foreach ($instance in $crInstances) {
                if ($instance.spec -and $instance.spec.PSObject.Properties.name -contains "secretName") {
                    $usedSecrets += $instance.spec.secretName
                }
            }
        }
    }

    $usedSecrets = $usedSecrets | Where-Object { $_ } | Sort-Object -Unique
    Write-Host "`r🤖 ✅ Secret usage checked. ($($usedSecrets.Count) in use)         " -ForegroundColor Green

    # Orphaned Secrets
    $orphanedSecrets = $secrets | Where-Object { $_.metadata.name -notin $usedSecrets }

    $orphanedItems = @()
    foreach ($sec in $orphanedSecrets) {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $sec.metadata.namespace
            Type      = "🔑 Secret"
            Name      = $sec.metadata.name
        }
    }

    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned Secrets found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔑 Orphaned Secrets]`n"
            Write-ToReport "✅ No orphaned Secrets found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html
    if ($Html) {
        $htmlTable = $orphanedItems |
        ConvertTo-Html -Fragment -Property Namespace, Type, Name -PreContent "<h2>Orphaned Secrets</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Orphaned Secrets Found:</strong> $($orphanedItems.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔑 Orphaned Secrets]`n"
        Write-ToReport "⚠️ Total Orphaned Secrets Found: $($orphanedItems.Count)"

        $tableString = $orphanedItems | Format-Table Namespace, Type, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems = $orphanedItems.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔑 Orphaned Secrets - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 Secrets store sensitive data such as API keys and credentials.",
            "",
            "📌 This check identifies Secrets that are NOT used by:",
            "   - Pods, Deployments, StatefulSets, DaemonSets.",
            "   - Ingress TLS, ServiceAccounts, and Custom Resources.",
            "",
            "⚠️ Unused Secrets may indicate outdated credentials or misconfigurations.",
            "",
            "⚠️ Total Orphaned Secrets Found: $($orphanedItems.Count)"
        )
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, Name -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-RBACOverexposure {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔓 RBAC Overexposure Check]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Analyzing Roles and Bindings..." -ForegroundColor Yellow

    $findings = @()

    # Get all roles and cluster roles
    $roles = kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoles = kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    if ($ExcludeNamespaces) {
        $roles = Exclude-Namespaces -items $roles
    }

    # Get bindings
    $roleBindings = kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoleBindings = kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    if ($ExcludeNamespaces) {
        $roleBindings = Exclude-Namespaces -items $roleBindings
    }
    
    # Find risky roles
    $wildcardRoles = @{}

    foreach ($cr in $clusterRoles) {
        foreach ($rule in $cr.rules) {
            if ($rule.verbs -contains "*" -and $rule.resources -contains "*" -and $rule.apiGroups -contains "*") {
                $wildcardRoles[$cr.metadata.name] = "ClusterRole"
                break
            }
        }
    }

    foreach ($r in $roles) {
        foreach ($rule in $r.rules) {
            if ($rule.verbs -contains "*" -and $rule.resources -contains "*" -and $rule.apiGroups -contains "*") {
                $wildcardRoles["$($r.metadata.namespace)/$($r.metadata.name)"] = "Role"
                break
            }
        }
    }

    # Check ClusterRoleBindings
    foreach ($crb in $clusterRoleBindings) {
        $roleName = $crb.roleRef.name
        $isClusterAdmin = ($roleName -eq "cluster-admin")
        $isWildcard = $wildcardRoles.ContainsKey($roleName)

        if ($isClusterAdmin -or $isWildcard) {
            foreach ($subject in $crb.subjects) {
                $findings += [PSCustomObject]@{
                    Namespace = "🌍 Cluster-Wide"
                    Binding   = $crb.metadata.name
                    Subject   = "$($subject.kind)/$($subject.name)"
                    Role      = $roleName
                    Scope     = "ClusterRoleBinding"
                    Risk      = if ($isClusterAdmin) { "❗ cluster-admin" } else { "⚠️ wildcard access" }
                }
            }
        }
    }

    # Check RoleBindings
    foreach ($rb in $roleBindings) {
        $roleName = $rb.roleRef.name
        $ns = $rb.metadata.namespace
        $key = "$ns/$roleName"
        $isClusterAdmin = ($roleName -eq "cluster-admin")
        $isWildcard = $wildcardRoles.ContainsKey($key)

        if ($isClusterAdmin -or $isWildcard) {
            foreach ($subject in $rb.subjects) {
                $findings += [PSCustomObject]@{
                    Namespace = $ns
                    Binding   = $rb.metadata.name
                    Subject   = "$($subject.kind)/$($subject.name)"
                    Role      = $roleName
                    Scope     = "RoleBinding"
                    Risk      = if ($isClusterAdmin) { "❗ cluster-admin" } else { "⚠️ wildcard access" }
                }
            }
        }
    }

    $total = $findings.Count
    Write-Host "`r🤖 ✅ Check complete. ($total high-risk bindings found)" -ForegroundColor Green

    if ($total -eq 0) {
        Write-Host "✅ No overexposed roles or bindings found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No RBAC overexposure detected.</strong></p>" }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
            Write-ToReport "✅ No cluster-admin or wildcard access detected."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        $htmlTable = $findings |
        ConvertTo-Html -Fragment -Property Namespace, Binding, Subject, Role, Scope, Risk -PreContent "<h2>RBAC Overexposure (cluster-admin or wildcard)</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Overexposed Bindings:</strong> $total</p>" + $htmlTable
        return $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
        Write-ToReport "⚠️ Total Overexposed Bindings: $total"
        $tableString = $findings | Format-Table Namespace, Binding, Subject, Role, Scope, Risk -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔓 RBAC Overexposure - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 This check identifies risky access via RBAC.",
            "",
            "📌 Included:",
            "   - cluster-admin grants (direct bindings)",
            "   - Custom Roles with * verbs, * resources, * apiGroups",
            "",
            "⚠️ These bindings may allow full control over your cluster.",
            "",
            "⚠️ Total Overexposed Bindings Found: $total"
        )

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $total)

        $pageData = $findings[$startIndex..($endIndex - 1)]
        $pageData | Format-Table Namespace, Binding, Subject, Role, Scope, Risk -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-RBACMisconfigurations {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan

    # Fetch RoleBindings & ClusterRoleBindings
    Write-Host -NoNewline "`n🤖 Fetching RoleBindings & ClusterRoleBindings..." -ForegroundColor Yellow
    $roleBindings = kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoleBindings = kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $roles = kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoles = kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    $existingNamespaces = kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

    if ($ExcludeNamespaces) {
        $roleBindings = Exclude-Namespaces -items $roleBindings
    }
    
    if ($ExcludeNamespaces) {
        $roles = Exclude-Namespaces -items $roles
    }
    

    Write-Host "`r🤖 ✅ Fetched $($roleBindings.Count) RoleBindings, $($clusterRoleBindings.Count) ClusterRoleBindings.`n" -ForegroundColor Green

    $invalidRBAC = @()

    Write-Host -NoNewline "🤖 Analyzing RBAC configurations..." -ForegroundColor Yellow

    # Evaluate RoleBindings
    foreach ($rb in $roleBindings) {
        $rbNamespace = $rb.metadata.namespace
        $namespaceExists = $rbNamespace -in $existingNamespaces

        # Check if the role exists in that namespace
        $roleExists = $roles | Where-Object { $_.metadata.name -eq $rb.roleRef.name -and $_.metadata.namespace -eq $rbNamespace }
        if (-not $roleExists -and $rb.roleRef.kind -eq "Role") {
            $invalidRBAC += [PSCustomObject]@{
                Namespace   = if ($namespaceExists) { $rbNamespace } else { "🛑 Namespace Missing" }
                Type        = "🔹 Namespace Role"
                RoleBinding = $rb.metadata.name
                Subject     = "N/A"
                Issue       = "❌ Missing Role: $($rb.roleRef.name)"
            }
        }
        # For RoleRef kind = "ClusterRole", you could check $clusterRoles if needed

        # Check each subject
        foreach ($subject in $rb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if (-not $namespaceExists) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🛑 Namespace Missing"
                        Type        = "🔹 Namespace Role"
                        RoleBinding = $rb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            Namespace   = $rbNamespace
                            Type        = "🔹 Namespace Role"
                            RoleBinding = $rb.metadata.name
                            Subject     = "$($subject.kind)/$($subject.name)"
                            Issue       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    # Evaluate ClusterRoleBindings
    foreach ($crb in $clusterRoleBindings) {
        foreach ($subject in $crb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if ($subject.namespace -notin $existingNamespaces) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🛑 Namespace Missing"
                        Type        = "🔸 Cluster Role"
                        RoleBinding = $crb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            Namespace   = "🌍 Cluster-Wide"
                            Type        = "🔸 Cluster Role"
                            RoleBinding = $crb.metadata.name
                            Subject     = "$($subject.kind)/$($subject.name)"
                            Issue       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    write-host  "`r🤖 ✅ RBAC configurations Checked.       " -ForegroundColor Green

    if ($invalidRBAC.Count -eq 0) {
        Write-Host "`r✅ No RBAC misconfigurations found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[RBAC Misconfigurations]`n"
            Write-ToReport "✅ No RBAC misconfigurations found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html, build an HTML table
    if ($Html) {
        if ($invalidRBAC.Count -eq 0) {
            return "<p><strong>✅ No RBAC misconfigurations found.</strong></p>"
        }
        $htmlTable = $invalidRBAC |
        ConvertTo-Html -Fragment -Property Namespace, Type, RoleBinding, Subject, Issue -PreContent "<h2>RBAC Misconfigurations</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total RBAC Misconfigurations Detected:</strong> $($invalidRBAC.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode
    if ($Global:MakeReport) {
        Write-ToReport "`n[RBAC Misconfigurations]`n"
        Write-ToReport "⚠️ Total RBAC Misconfigurations Detected: $($invalidRBAC.Count)"

        $tableString = $invalidRBAC | Format-Table Namespace, Type, RoleBinding, Subject, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, do pagination
    $totalBindings = $invalidRBAC.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalBindings / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[RBAC Misconfigurations - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 RBAC (Role-Based Access Control) defines who can do what in your cluster.",
            "",
            "📌 This check identifies:",
            "   - 🔍 Misconfigurations in RoleBindings & ClusterRoleBindings.",
            "   - ❌ Missing references to ServiceAccounts & Namespaces.",
            "   - 🔓 Overly permissive roles that may pose security risks.",
            "",
            "⚠️ Total RBAC Misconfigurations Detected: $totalBindings"
        )
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalBindings)

        $tableData = $invalidRBAC[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, RoleBinding, Subject, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-HostPidAndNetwork {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔌 Pods with hostPID / hostNetwork]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($($pods.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Scanning for hostPID / hostNetwork usage..." -ForegroundColor Yellow

    $flaggedPods = @()

    foreach ($pod in $pods) {
        $hostPID = $pod.spec.hostPID
        $hostNetwork = $pod.spec.hostNetwork

        if ($hostPID -or $hostNetwork) {
            $flaggedPods += [PSCustomObject]@{
                Namespace   = $pod.metadata.namespace
                Pod         = $pod.metadata.name
                hostPID     = if ($hostPID-eq "true") { "❌ true" } else { "✅ false" }
                hostNetwork = if ($hostNetwork -eq "true") { "❌ true" } else { "✅ false" }                
            }
            
        }
    }

    Write-Host "`r🤖 ✅ Scan complete. ($($flaggedPods.Count) flagged)              " -ForegroundColor Green

    if ($flaggedPods.Count -eq 0) {
        Write-Host "✅ No pods with hostPID or hostNetwork found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔌 Pods with hostPID / hostNetwork]`n"
            Write-ToReport "✅ No pods with hostPID or hostNetwork found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        if ($flaggedPods.Count -eq 0) {
            return "<p><strong>✅ No pods with hostPID or hostNetwork found.</strong></p>"
        }
        $htmlTable = $flaggedPods |
        ConvertTo-Html -Fragment -Property Namespace, Pod, hostPID, hostNetwork -PreContent "<h2>Pods with hostPID / hostNetwork</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Flagged Pods:</strong> $($flaggedPods.Count)</p>" + $htmlTable
        return $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔌 Pods with hostPID / hostNetwork]`n"
        Write-ToReport "⚠️ Total Flagged Pods: $($flaggedPods.Count)"

        $tableString = $flaggedPods | Format-Table Namespace, Pod, hostPID, hostNetwork -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems = $flaggedPods.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔌 Pods with hostPID / hostNetwork - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $flaggedPods[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, hostPID, hostNetwork -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PodsRunningAsRoot {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[👑 Pods Running as Root]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

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
                    Namespace   = $pod.metadata.namespace
                    Pod         = $pod.metadata.name
                    Container   = $container.name
                    runAsUser   = if ($containerUser) { $containerUser } elseif ($podUser) { $podUser } else { "Not Set (Defaults to root)" }
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
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        if ($rootPods.Count -eq 0) {
            return "<p><strong>✅ No pods running as root.</strong></p>"
        }
        $htmlTable = $rootPods |
        ConvertTo-Html -Fragment -Property Namespace, Pod, Container, runAsUser -PreContent "<h2>Pods Running as Root</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Pods Running as Root:</strong> $($rootPods.Count)</p>" + $htmlTable
        return $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[👑 Pods Running as Root]`n"
        Write-ToReport "⚠️ Total Pods Running as Root: $($rootPods.Count)"

        $tableString = $rootPods | Format-Table Namespace, Pod, Container, runAsUser -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems = $rootPods.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[👑 Pods Running as Root - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $rootPods[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Container, runAsUser -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PrivilegedContainers {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔓 Privileged Containers]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pods..." -ForegroundColor Yellow

    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($($pods.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Scanning for privileged containers..." -ForegroundColor Yellow

    $privileged = @()

    foreach ($pod in $pods) {
        foreach ($container in $pod.spec.containers) {
            $isPrivileged = $container.securityContext.privileged
            if ($isPrivileged) {
                $privileged += [PSCustomObject]@{
                    Namespace  = $pod.metadata.namespace
                    Pod        = $pod.metadata.name
                    Container  = $container.name
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
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Html) {
        if ($privileged.Count -eq 0) {
            return "<p><strong>✅ No privileged containers found.</strong></p>"
        }
        $htmlTable = $privileged |
        ConvertTo-Html -Fragment -Property Namespace, Pod, Container -PreContent "<h2>Privileged Containers</h2>" |
        Out-String

        $htmlTable = "<p><strong>⚠️ Total Privileged Containers Found:</strong> $($privileged.Count)</p>" + $htmlTable
        return $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔓 Privileged Containers]`n"
        Write-ToReport "⚠️ Total Privileged Containers Found: $($privileged.Count)"

        $tableString = $privileged | Format-Table Namespace, Pod, Container -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems = $privileged.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔓 Privileged Containers - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $privileged[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Container -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
