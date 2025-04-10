function Get-KubeData {
    param (
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$ExcludeNamespaces,
        [switch]$AKS
    )

    # Ensure kubectl is available and functional
    # 1. Check if kubectl is installed
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Host "❌ kubectl is not installed or not in PATH. Please install kubectl and ensure it's accessible." -ForegroundColor Red
        return
        return $false  # return error flag
    }

    # 2. Check kubectl version (client only)
    $kubectlVersionOutput = kubectl version --client 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ kubectl is installed but not functioning correctly." -ForegroundColor Red
        Write-Host "🧾 Error: $kubectlVersionOutput" -ForegroundColor DarkGray
        return $false  # return error flag
        return
    }

    # 3. Verify cluster communication
    $kubectlClusterCheck = kubectl get namespaces --no-headers -o custom-columns=NAME:.metadata.name 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $kubectlClusterCheck) {
        Write-Host "❌ kubectl cannot communicate with the Kubernetes cluster." -ForegroundColor Red
        Write-Host "🧾 Error: $kubectlClusterCheck" -ForegroundColor DarkGray
        return $false  # return error flag
        return
    }

    Write-Host "✅ kubectl is available and connected to the cluster." -ForegroundColor Green

    $data = @{}
    $resources = @(
        @{ Name = "Pods"; Cmd = { kubectl get pods --all-namespaces -o json }; Key = "Pods"; Items = $false },
        @{ Name = "Nodes"; Cmd = { kubectl get nodes -o json }; Key = "Nodes"; Items = $false },
        @{ Name = "Top Nodes"; Cmd = { kubectl top nodes --no-headers }; Key = "TopNodes"; Raw = $true },
        @{ Name = "Namespaces"; Cmd = { kubectl get namespaces -o json }; Key = "Namespaces"; Items = $true },
        @{ Name = "Events"; Cmd = { kubectl get events --all-namespaces -o json }; Key = "Events"; Items = $true },
        @{ Name = "Jobs"; Cmd = { kubectl get jobs --all-namespaces -o json }; Key = "Jobs"; Items = $true },
        @{ Name = "DaemonSets"; Cmd = { kubectl get daemonsets --all-namespaces -o json }; Key = "DaemonSets"; Items = $true },
        @{ Name = "StatefulSets"; Cmd = { kubectl get statefulsets --all-namespaces -o json }; Key = "StatefulSets"; Items = $true },
        @{ Name = "Deployments"; Cmd = { kubectl get deployments --all-namespaces -o json }; Key = "Deployments"; Items = $true },
        @{ Name = "PodDisruptionBudgets"; Cmd = { kubectl get pdb --all-namespaces -o json }; Key = "PodDisruptionBudgets"; Items = $true },
        @{ Name = "HorizontalPodAutoscalers"; Cmd = { kubectl get hpa --all-namespaces -o json }; Key = "HorizontalPodAutoscalers"; Items = $true },
        @{ Name = "Services"; Cmd = { kubectl get svc --all-namespaces -o json }; Key = "Services"; Items = $false },
        @{ Name = "Ingresses"; Cmd = { kubectl get ingress --all-namespaces -o json }; Key = "Ingresses"; Items = $true },
        @{ Name = "Endpoints"; Cmd = { kubectl get endpoints --all-namespaces -o json }; Key = "Endpoints"; Items = $false },
        @{ Name = "ConfigMaps"; Cmd = { kubectl get configmaps --all-namespaces -o json }; Key = "ConfigMaps"; Items = $true },
        @{ Name = "Secrets"; Cmd = { kubectl get secrets --all-namespaces -o json }; Key = "Secrets"; Items = $true },
        @{ Name = "PersistentVolumes"; Cmd = { kubectl get pv -o json }; Key = "PersistentVolumes"; Items = $true },
        @{ Name = "PersistentVolumeClaims"; Cmd = { kubectl get pvc --all-namespaces -o json }; Key = "PersistentVolumeClaims"; Items = $true },
        @{ Name = "NetworkPolicies"; Cmd = { kubectl get networkpolicies --all-namespaces -o json }; Key = "NetworkPolicies"; Items = $true },
        @{ Name = "Roles"; Cmd = { kubectl get roles --all-namespaces -o json }; Key = "Roles"; Items = $true },
        @{ Name = "RoleBindings"; Cmd = { kubectl get rolebindings --all-namespaces -o json }; Key = "RoleBindings"; Items = $true },
        @{ Name = "ClusterRoles"; Cmd = { kubectl get clusterroles -o json }; Key = "ClusterRoles"; Items = $true },
        @{ Name = "ClusterRoleBindings"; Cmd = { kubectl get clusterrolebindings -o json }; Key = "ClusterRoleBindings"; Items = $true },
        @{ Name = "ServiceAccounts"; Cmd = { kubectl get serviceaccounts --all-namespaces -o json }; Key = "ServiceAccounts"; Items = $true }
    )

    Write-Host "`n[📦 Gathering Kubernetes Resource Data]" -ForegroundColor Cyan
    $totalResources = $resources.Count

    $results = $resources | ForEach-Object -Parallel {
        Import-Module Microsoft.PowerShell.Utility -Cmdlet Write-Host, ConvertFrom-Json

        $res = $_
        $output = [PSCustomObject]@{
            Key     = $res.Key
            Label   = $res.Name
            Raw     = $res.Raw
            Value   = $null
            Success = $true
            Error   = $null
        }

        Write-Host "▶️ Starting $($res.Name)" -ForegroundColor Yellow

        try {
            $result = & $res.Cmd
            if ($null -ne $result) {
                if ($res.Raw) {
                    $output.Value = @($result -split "`n" | Where-Object { $_ })
                }
                else {
                    $jsonResult = $result | ConvertFrom-Json
                    $output.Value = if ($res.Items) { $jsonResult.items } else { $jsonResult }
                }
            }
            else {
                $output.Value = @()
            }
        }
        catch {
            $output.Success = $false
            $output.Error = $_.Exception.Message
        }

        Write-Host "✔️ Finished $($res.Name)" -ForegroundColor Cyan
        return $output
    } -ThrottleLimit 8 

    # Show progress based on completed results
    $completed = $results.Count
    $percentComplete = ([int]($completed / $totalResources * 100))
    Write-Progress -Activity "Gathering Kubernetes Resources" `
        -Status "$completed/$totalResources ($percentComplete%)" `
        -PercentComplete $percentComplete
    Write-Progress -Activity "Gathering Kubernetes Resources" -Completed

    Write-Host "`n[📋 Results]" -ForegroundColor Cyan
    foreach ($r in $results) {
        if ($r.Success) {
            Write-Host "✅ $($r.Label)" -ForegroundColor Green
            $data[$r.Key] = $r.Value
        }
        else {
            Write-Host "❌ $($r.Label): $($r.Error)" -ForegroundColor Red
            throw "Critical error: Stopping execution due to failure in $($r.Label) - $($r.Error)"
            exit 1
        }
    }

    # Custom Resources (run serially)
    Write-Host -NoNewline "`n🤖 Fetching Custom Resource Instances..." -ForegroundColor Yellow
    $data.CustomResourcesByKind = @{}
    try {
        $crds = kubectl get crds -o json | ConvertFrom-Json
        foreach ($crd in $crds.items) {
            $kind = $crd.spec.names.kind
            $plural = $crd.spec.names.plural
            $group = $crd.spec.group
            $version = ($crd.spec.versions | Where-Object { $_.served -and $_.storage } | Select-Object -First 1).name
            if (-not $version) { $version = $crd.spec.versions[0].name }

            $apiversion = "$group/$version"
            try {
                $items = kubectl get $plural --all-namespaces -o json --api-version=$apiversion 2>$null | ConvertFrom-Json
                $data.CustomResourcesByKind[$kind] = $items.items
            }
            catch {}
        }
        Write-Host "`r✅ Custom Resource Instances fetched.   " -ForegroundColor Green
    }
    catch {
        Write-Host "`r❌ Failed to fetch CRDs or CR Instances: $($_.Exception.Message)" -ForegroundColor Red
        throw "Critical error: Stopping execution due to failure in fetching Custom Resources - $($_.Exception.Message)"
    }

    # AKS Metadata (only if needed)
    if ($AKS -and $ResourceGroup -and $ClusterName) {
        Write-Host -NoNewline "`n🤖 Fetching AKS Metadata..." -ForegroundColor Yellow
        try {
            $data.AksCluster = az aks show --resource-group $ResourceGroup --name $ClusterName --only-show-errors | ConvertFrom-Json
            Write-Host "`r✅ AKS Metadata fetched.   " -ForegroundColor Green

            Write-Host -NoNewline "`n🤖 Fetching Constraints..." -ForegroundColor Yellow
            $data.ConstraintTemplates = @( (kubectl get constrainttemplates -o json | ConvertFrom-Json).items )
            $data.Constraints = @( (kubectl get constraints -A -o json | ConvertFrom-Json).items )
            Write-Host "`r✅ Constraints fetched.   " -ForegroundColor Green
        }
        catch {
            Write-Host "`r❌ Failed to fetch AKS Metadata or Constraints: $($_.Exception.Message)" -ForegroundColor Red
            throw "Critical error: Stopping execution due to failure in fetching AKS Metadata or Constraints - $($_.Exception.Message)"
        }
    }

    # Namespace filtering
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