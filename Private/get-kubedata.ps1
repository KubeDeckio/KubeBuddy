function Get-KubeData {
    param (
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$ExcludeNamespaces,
        [switch]$AKS
    )

    $data = @{}

    try {
        Write-Host "`n[📦 Gathering Kubernetes Resource Data]" -ForegroundColor Cyan

        Write-Host -NoNewline "`n🤖 📄 Fetching Pods..." -ForegroundColor Yellow
        $data.Pods = @( (kubectl get pods --all-namespaces -o json | ConvertFrom-Json))
        Write-Host "`r🤖 📄 Pods fetched.         " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🧱 Fetching Nodes..." -ForegroundColor Yellow
        $data.Nodes = @( (kubectl get nodes -o json | ConvertFrom-Json) )
        Write-Host "`r🤖 🧱 Nodes fetched.        " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🧱 Fetching Top Nodes..." -ForegroundColor Yellow
        $data.TopNodes = @( kubectl top nodes --no-headers )
        Write-Host "`r🤖 🧱 Top Nodes fetched.        " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 📂 Fetching Namespaces..." -ForegroundColor Yellow
        $data.Namespaces = @( (kubectl get namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 📂 Namespaces fetched.    " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 📋 Fetching Events..." -ForegroundColor Yellow
        $data.Events = @( (kubectl get events --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 📋 Events fetched.        " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🔁 Fetching Jobs..." -ForegroundColor Yellow
        $data.Jobs = @( (kubectl get jobs --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 🔁 Jobs fetched.          " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 📦 Fetching DaemonSets..." -ForegroundColor Yellow
        $data.DaemonSets = @( (kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 📦 DaemonSets fetched.    " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 📦 Fetching StatefulSets..." -ForegroundColor Yellow
        $data.StatefulSets = @( (kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 📦 StatefulSets fetched.   " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🚀 Fetching Deployments..." -ForegroundColor Yellow
        $data.Deployments = @( (kubectl get deployments --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 🚀 Deployments fetched.   " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🔌 Fetching Services..." -ForegroundColor Yellow
        $data.Services = @( (kubectl get svc --all-namespaces -o json | ConvertFrom-Json))
        Write-Host "`r🤖 🔌 Services fetched.      " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🔌 Fetching Endpoints..." -ForegroundColor Yellow
        $data.Endpoints = @( (kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json))
        Write-Host "`r🤖 🔌 Endpoints fetched.      " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 💾 Fetching PersistentVolumes..." -ForegroundColor Yellow
        $data.PersistentVolumes = @( (kubectl get pv -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 💾 PersistentVolumes fetched.   " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 📦 Fetching PersistentVolumeClaims..." -ForegroundColor Yellow
        $data.PersistentVolumeClaims = @( (kubectl get pvc --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 📦 PersistentVolumeClaims fetched.   " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🔒 Fetching Network Policies..." -ForegroundColor Yellow
        $data.NetworkPolicies = @( (kubectl get networkpolicies --all-namespaces -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 🔒 Network Policies fetched.   " -ForegroundColor Green

        Write-Host -NoNewline "`n🤖 🔐 Fetching Roles and Bindings..." -ForegroundColor Yellow
        $data.Roles = @( (kubectl get roles --all-namespaces -o json | ConvertFrom-Json).items )
        $data.RoleBindings = @( (kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json).items )
        $data.ClusterRoles = @( (kubectl get clusterroles -o json | ConvertFrom-Json).items )
        $data.ClusterRoleBindings = @( (kubectl get clusterrolebindings -o json | ConvertFrom-Json).items )
        Write-Host "`r🤖 🔐 Roles and Bindings fetched.   " -ForegroundColor Green

        if ($AKS -and $ResourceGroup -and $ClusterName) {
            Write-Host -NoNewline "`n🤖 ☁️ Fetching AKS Metadata..." -ForegroundColor Yellow
            $data.AksCluster = az aks show --resource-group $ResourceGroup --name $ClusterName | ConvertFrom-Json
            Write-Host "`r🤖 ☁️ AKS Metadata fetched.       " -ForegroundColor Green

            Write-Host -NoNewline "`n🤖 📏 Fetching Gatekeeper and Azure Policy constraints..." -ForegroundColor Yellow
            $data.ConstraintTemplates = @( (kubectl get constrainttemplates -o json | ConvertFrom-Json).items )
            $data.Constraints = @( (kubectl get constraints -A -o json | ConvertFrom-Json).items )
            Write-Host "`r🤖 📏 Constraints fetched.                             " -ForegroundColor Green
        }

    } catch {
        Write-Host "`r🤖 ❌ Error during kubectl or az call: $_" -ForegroundColor Red
        $data.Error = $_.Exception.Message
        return $data
    }

    if ($ExcludeNamespaces) {
        Write-Host "`n🤖 🚫 Excluding selected namespaces..." -ForegroundColor Yellow
        foreach ($key in @(
            'Pods', 'Jobs', 'Deployments', 'Services',
            'DaemonSets', 'StatefulSets', 'PersistentVolumeClaims',
            'Events', 'NetworkPolicies', 'Roles', 'RoleBindings',
            'Constraints', 'AzPolicies', 'K8sAzureConstraints'
        )) {
            if ($data.ContainsKey($key)) {
                $data[$key] = Exclude-Namespaces -items $data[$key]
            }
        }
    }

    return $data
}
