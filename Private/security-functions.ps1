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
                $key = "$($r.metadata.namespace)/$($r.metadata.name)"
                $wildcardRoles[$key] = "Role"
                break
            }
        }
    }

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
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
            Write-ToReport "✅ No cluster-admin or wildcard access detected."
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
            ConvertTo-Html -Fragment -Property Namespace, Binding, Subject, Role, Scope, Risk -PreContent "<h2>RBAC Overexposure (cluster-admin or wildcard)</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Overexposed Bindings:</strong> $total</p>$htmlTable"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔓 RBAC Overexposure Check]`n"
        Write-ToReport "⚠️ Total Overexposed Bindings: $total"
        $tableString = $findings | Format-Table Namespace, Binding, Subject, Role, Scope, Risk -AutoSize | Out-String
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
                "",
                "⚠️ These bindings may allow full control over your cluster.",
                "",
                "⚠️ Total Overexposed Bindings Found: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $findings | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Binding, Subject, Role, Scope, Risk -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Check-RBACMisconfigurations {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching RoleBindings & ClusterRoleBindings..." -ForegroundColor Yellow

    try {
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

        $existingNamespaces = if ($KubeData -and $KubeData.Namespaces) {
            $KubeData.Namespaces | ForEach-Object { $_.metadata.name }
        } else {
            kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | ForEach-Object { $_.metadata.name }
        }

        $serviceAccounts = if ($KubeData -and $KubeData.ServiceAccounts) {
            $KubeData.ServiceAccounts
        } else {
            kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving RBAC data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $roleBindings = Exclude-Namespaces -items $roleBindings
        $roles = Exclude-Namespaces -items $roles
    }

    Write-Host "`r🤖 ✅ Fetched $($roleBindings.Count) RoleBindings, $($clusterRoleBindings.Count) ClusterRoleBindings.`n" -ForegroundColor Green
    Write-Host -NoNewline "🤖 Analyzing RBAC configurations..." -ForegroundColor Yellow

    $invalidRBAC = @()

    foreach ($rb in $roleBindings) {
        $rbNamespace = $rb.metadata.namespace
        $namespaceExists = $rbNamespace -in $existingNamespaces

        $roleExists = $roles | Where-Object {
            $_.metadata.name -eq $rb.roleRef.name -and $_.metadata.namespace -eq $rbNamespace
        }

        if (-not $roleExists -and $rb.roleRef.kind -eq "Role") {
            $invalidRBAC += [PSCustomObject]@{
                Namespace   = if ($namespaceExists) { $rbNamespace } else { "🚩 Namespace Missing" }
                Type        = "🔹 Namespace Role"
                RoleBinding = $rb.metadata.name
                Subject     = "N/A"
                Issue       = "❌ Missing Role: $($rb.roleRef.name)"
            }
        }

        foreach ($subject in $rb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if (-not $namespaceExists) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🚩 Namespace Missing"
                        Type        = "🔹 Namespace Role"
                        RoleBinding = $rb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🚩 Namespace does not exist"
                    }
                } else {
                    $exists = $serviceAccounts | Where-Object {
                        $_.metadata.name -eq $subject.name -and $_.metadata.namespace -eq $subject.namespace
                    }
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

    foreach ($crb in $clusterRoleBindings) {
        foreach ($subject in $crb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if ($subject.namespace -notin $existingNamespaces) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🚩 Namespace Missing"
                        Type        = "🔸 Cluster Role"
                        RoleBinding = $crb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🚩 Namespace does not exist"
                    }
                } else {
                    $exists = $serviceAccounts | Where-Object {
                        $_.metadata.name -eq $subject.name -and $_.metadata.namespace -eq $subject.namespace
                    }
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

    Write-Host "`r🤖 ✅ RBAC configurations Checked.       " -ForegroundColor Green

    if ($invalidRBAC.Count -eq 0) {
        Write-Host "`r✅ No RBAC misconfigurations found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No RBAC misconfigurations found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[RBAC Misconfigurations]`n"
            Write-ToReport "✅ No RBAC misconfigurations found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $invalidRBAC.Count; Items = $invalidRBAC }
    }

    if ($Html) {
        $htmlTable = $invalidRBAC |
            ConvertTo-Html -Fragment -Property Namespace, Type, RoleBinding, Subject, Issue -PreContent "<h2>RBAC Misconfigurations</h2>" |
            Out-String
        return "<p><strong>⚠️ Total RBAC Misconfigurations Detected:</strong> $($invalidRBAC.Count)</p>$htmlTable"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[RBAC Misconfigurations]`n"
        Write-ToReport "⚠️ Total RBAC Misconfigurations Detected: $($invalidRBAC.Count)"
        $tableString = $invalidRBAC | Format-Table Namespace, Type, RoleBinding, Subject, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $total = $invalidRBAC.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[RBAC Misconfigurations - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 RBAC (Role-Based Access Control) defines who can do what in your cluster.",
                "",
                "📌 This check identifies:",
                "   - 🔍 Misconfigurations in RoleBindings & ClusterRoleBindings.",
                "   - ❌ Missing references to ServiceAccounts & Namespaces.",
                "   - 🔓 Overly permissive roles that may pose security risks.",
                "",
                "⚠️ Total RBAC Misconfigurations Detected: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $invalidRBAC | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Type, RoleBinding, Subject, Issue -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

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
        $sas = Exclude-Namespaces -items $sas
        $roleBindings = Exclude-Namespaces -items $roleBindings
        $pods = Exclude-Namespaces -items $pods
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
        $html = $items |
            ConvertTo-Html -Fragment -Property Namespace, Name |
            Out-String
        return "<p><strong>⚠️ Orphaned ServiceAccounts:</strong> $total</p>" + $html
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
    }
    catch {
        Write-Host "`r🤖 ❌ Error fetching RBAC data: $_" -ForegroundColor Red
        return
    }

    if ($ExcludeNamespaces) {
        $roles = Exclude-Namespaces -items $roles
        $roleBindings = Exclude-Namespaces -items $roleBindings
    }

    $usedRoleNames = [System.Collections.Generic.HashSet[string]]::new()
    $usedClusterRoleNames = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($rb in $roleBindings) {
        if ($rb.roleRef.kind -eq "Role") {
            $usedRoleNames.Add("$($rb.metadata.namespace)/$($rb.roleRef.name)") | Out-Null
        }
        elseif ($rb.roleRef.kind -eq "ClusterRole") {
            $usedClusterRoleNames.Add($rb.roleRef.name) | Out-Null
        }
    }

    foreach ($crb in $clusterRoleBindings) {
        if ($crb.roleRef.kind -eq "ClusterRole") {
            $usedClusterRoleNames.Add($crb.roleRef.name) | Out-Null
        }
    }

    $results = @()

    foreach ($r in $roles) {
        $key = "$($r.metadata.namespace)/$($r.metadata.name)"
        if (-not $usedRoleNames.Contains($key)) {
            $results += [PSCustomObject]@{
                Namespace = $r.metadata.namespace
                Role      = $r.metadata.name
                Type      = "Role"
            }
        }
    }

    foreach ($cr in $clusterRoles) {
        if (-not $usedClusterRoleNames.Contains($cr.metadata.name)) {
            $results += [PSCustomObject]@{
                Namespace = "🌍 Cluster-Wide"
                Role      = $cr.metadata.name
                Type      = "ClusterRole"
            }
        }
    }

    $total = $results.Count
    Write-Host "`r🤖 ✅ RBAC analysis complete. ($total unused roles found)" -ForegroundColor Green

    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ No unused roles or clusterroles found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🗂️ Unused Roles & ClusterRoles]`n✅ No unused roles."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $total; Items = $results }
    }

    if ($Html) {
        $html = $results |
            ConvertTo-Html -Fragment -Property Namespace, Role, Type |
            Out-String
        return "<p><strong>⚠️ Unused Roles:</strong> $total</p>" + $html
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🗂️ Unused Roles & ClusterRoles]`n⚠️ Total: $total"
        $tableString = $results | Format-Table Namespace, Role, Type -AutoSize | Out-String
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
                "🤖 These Roles and ClusterRoles are not referenced by any bindings.",
                "",
                "📌 Why this matters:",
                "   - Unused roles add clutter and confusion.",
                "   - May be leftovers from uninstalled apps.",
                "",
                "⚠️ Total unused roles: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Role, Type -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
