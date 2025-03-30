function Get-KubeData {
    param (
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$ExcludeNamespaces,
        [switch]$AKS
    )

    $data = @{}
    $resources = @(
        @{ Name = "Pods"; Cmd = { kubectl get pods --all-namespaces -o json | ConvertFrom-Json }; Key = "Pods" },
        @{ Name = "Nodes"; Cmd = { kubectl get nodes -o json | ConvertFrom-Json }; Key = "Nodes" },
        @{ Name = "Top Nodes"; Cmd = { kubectl top nodes --no-headers }; Key = "TopNodes"; Raw = $true },
        @{ Name = "Namespaces"; Cmd = { (kubectl get namespaces -o json | ConvertFrom-Json).items }; Key = "Namespaces" },
        @{ Name = "Events"; Cmd = { (kubectl get events --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Events" },
        @{ Name = "Jobs"; Cmd = { (kubectl get jobs --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Jobs" },
        @{ Name = "DaemonSets"; Cmd = { (kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json).items }; Key = "DaemonSets" },
        @{ Name = "StatefulSets"; Cmd = { (kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json).items }; Key = "StatefulSets" },
        @{ Name = "Deployments"; Cmd = { (kubectl get deployments --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Deployments" },
        @{ Name = "Services"; Cmd = { kubectl get svc --all-namespaces -o json | ConvertFrom-Json }; Key = "Services" },
        @{ Name = "Ingresses"; Cmd = { (kubectl get ingress --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Ingresses" },
        @{ Name = "Endpoints"; Cmd = { kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json }; Key = "Endpoints" },
        @{ Name = "ConfigMaps"; Cmd = { (kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json).items }; Key = "ConfigMaps" },
        @{ Name = "Secrets"; Cmd = { (kubectl get secrets --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Secrets" },
        @{ Name = "PersistentVolumes"; Cmd = { (kubectl get pv -o json | ConvertFrom-Json).items }; Key = "PersistentVolumes" },
        @{ Name = "PersistentVolumeClaims"; Cmd = { (kubectl get pvc --all-namespaces -o json | ConvertFrom-Json).items }; Key = "PersistentVolumeClaims" },
        @{ Name = "NetworkPolicies"; Cmd = { (kubectl get networkpolicies --all-namespaces -o json | ConvertFrom-Json).items }; Key = "NetworkPolicies" },
        @{ Name = "Roles"; Cmd = { (kubectl get roles --all-namespaces -o json | ConvertFrom-Json).items }; Key = "Roles" },
        @{ Name = "RoleBindings"; Cmd = { (kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json).items }; Key = "RoleBindings" },
        @{ Name = "ClusterRoles"; Cmd = { (kubectl get clusterroles -o json | ConvertFrom-Json).items }; Key = "ClusterRoles" },
        @{ Name = "ClusterRoleBindings"; Cmd = { (kubectl get clusterrolebindings -o json | ConvertFrom-Json).items }; Key = "ClusterRoleBindings" },
        @{ Name = "ServiceAccounts"; Cmd = { (kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json).items }; Key = "ServiceAccounts" },
        @{ Name = "CRDs"; Cmd = { (kubectl get crds -o json | ConvertFrom-Json).items }; Key = "CRDs" }
    )

    try {
        Write-Host "`n[📦 Gathering Kubernetes Resource Data]" -ForegroundColor Cyan
        $total = $resources.Count
        $index = 0

        foreach ($res in $resources) {
            $index++
            $label = $res.Name
            Write-Host -NoNewline "[$index/$total] Fetching $label... " -ForegroundColor Cyan

            try {
                $value = & $res.Cmd
                $data[$res.Key] = if ($res.Raw) { @($value) } else { $value }
                Write-Host "✅" -ForegroundColor Green
            } catch {
                Write-Host "❌ $_" -ForegroundColor Red
            }
        }

        # Custom Resources
        Write-Host "`n🤖 Fetching Custom Resource Instances..." -ForegroundColor Yellow
        $data.CustomResourcesByKind = @{}

        if ($data.CRDs -and $data.CRDs.Count -gt 0) {
            foreach ($crd in $data.CRDs) {
                $kind = $crd.spec.names.kind
                $plural = $crd.spec.names.plural
                $group = $crd.spec.group
                $version = ($crd.spec.versions | Where-Object { $_.served -and $_.storage } | Select-Object -First 1).name
                if (-not $version) { $version = $crd.spec.versions[0].name }

                if ($kind -match "^[a-z0-9-]+$") {
                    try {
                        $apiversion = "$group/$version"
                        $items = kubectl get $plural --all-namespaces -o json --api-version=$apiversion 2>$null | ConvertFrom-Json
                        $data.CustomResourcesByKind[$kind] = $items.items
                    } catch { }
                }
            }
            Write-Host "✅ Custom Resource Instances fetched." -ForegroundColor Green
        }

        if ($AKS -and $ResourceGroup -and $ClusterName) {
            Write-Host "`n🤖 Fetching AKS Metadata..." -ForegroundColor Yellow
            $data.AksCluster = az aks show --resource-group $ResourceGroup --name $ClusterName | ConvertFrom-Json
            Write-Host "✅ AKS Metadata fetched." -ForegroundColor Green

            Write-Host "🤖 Fetching Constraints..." -ForegroundColor Yellow
            $data.ConstraintTemplates = @( (kubectl get constrainttemplates -o json | ConvertFrom-Json).items )
            $data.Constraints = @( (kubectl get constraints -A -o json | ConvertFrom-Json).items )
            Write-Host "✅ Constraints fetched." -ForegroundColor Green
        }

    } catch {
        Write-Host "`n❌ General error during fetch: $_" -ForegroundColor Red
        $data.Error = $_.Exception.Message
        return $data
    }

    if ($ExcludeNamespaces) {
        Write-Host "`n🤖 🚫 Excluding selected namespaces..." -ForegroundColor Yellow
        foreach ($key in @(
            'Pods', 'Jobs', 'Deployments', 'Services',
            'DaemonSets', 'StatefulSets', 'PersistentVolumeClaims',
            'Events', 'NetworkPolicies', 'Roles', 'RoleBindings',
            'Constraints'
        )) {
            if ($data.ContainsKey($key)) {
                $data[$key] = Exclude-Namespaces -items $data[$key]
            }
        }
    }

    return $data
}
