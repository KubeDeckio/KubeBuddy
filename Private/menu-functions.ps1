function show-mainMenu {
    param(
        [switch]$ExcludeNamespaces
    )
    do {
        if ($firstRun) {
            $firstRun = $false
        }
        else {
            Clear-Host
        }
        Write-Host "`n[🏠  Main Menu]" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor DarkGray

        # Main menu options
        $options = @(
            "[1]  Cluster Summary 📊"
            "[2]  Node Details 🖥️"
            "[3]  Namespace Management 📂"
            "[4]  Workload Management ⚙️"
            "[5]  Pod Management 🚀"
            "[6]  Kubernetes Jobs 🏢"
            "[7]  Service & Networking 🌐"
            "[8]  Storage Management 📦"
            "[9]  RBAC & Security 🔐"
            "[10] ConfigMap Hygiene 🧹"
            "[11] Cluster Warning Events ⚠️"
            "[12] Infrastructure Best Practices ✅"
            "[Q]  Exit ❌"
        )
    
        foreach ($option in $options) { Write-Host $option }
    
        # Get user choice
        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host
    
        switch ($choice) {
            "1" { Show-ClusterSummary }
            "2" { $result = Show-NodeMenu; if ($result -eq "exit") { return } }
            "3" { $result = Show-NamespaceMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "4" { $result = Show-WorkloadMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "5" { $result = Show-PodMenu; if ($result -eq "exit") { return } }
            "6" { $result = Show-JobsMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "7" { $result = Show-ServiceMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "8" { $result = Show-StorageMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "9" { $result = Show-RBACMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "10" { $result = Show-ConfigMapHygieneMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "11" { $result = Show-KubeEventsMenu -ExcludeNamespaces:$ExcludeNamespaces; if ($result -eq "exit") { return } }
            "12" { $result = Show-InfraBestPracticesMenu; if ($result -eq "exit") { return } }
            "Q" { Write-Host "👋 Goodbye! Have a great day! 🚀"; return }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }
    
    } while ($true)
}

function Show-WorkloadMenu {
    do {
        Clear-Host
        Write-Host "`n[⚙️  Workload Management]" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor DarkGray

        $options = @(
            "[1]  Check DaemonSet Health 🛠️",
            "[2]  Check Deployment Issues 🚀",
            "[3]  Check StatefulSet Issues 🏗️",
            "[4]  Check ReplicaSet Health 📈",
            "[5]  Check HPA Status ⚖️",
            "[6]  Check Missing Resources & Limits 🛟",
            "[7]  Check missing or weak PodDisruptionBudgets 🛡️",
            "[8]  Check containers missing health probes 🔎",
            "[9]  Check Deployment selectors with no matching pods ❌",
            "🔙  Back [B] | ❌ Exit [Q]"
        )


        foreach ($option in $options) { Write-Host $option }

        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($choice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "WRK001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "WRK002" -ExcludeNamespaces:$ExcludeNamespaces }
            "3" { Show-YamlCheckInteractive -CheckIDs "WRK003" -ExcludeNamespaces:$ExcludeNamespaces }
            "4" {
                $msg = @(
                    "🤖 ReplicaSet Health Check is coming soon!",
                    "",
                    "   - This feature will monitor ReplicaSets for pod mismatches, scaling issues, and failures.",
                    "   - Coming soon! 📈"
                )
                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50
                Read-Host "🤖 Press Enter to return to the menu"
            }
            "5" { Show-YamlCheckInteractive -CheckIDs "WRK004" -ExcludeNamespaces:$ExcludeNamespaces }
            "6" { Show-YamlCheckInteractive -CheckIDs "WRK005" -ExcludeNamespaces:$ExcludeNamespaces }
            "7" { Show-YamlCheckInteractive -CheckIDs "WRK006" -ExcludeNamespaces:$ExcludeNamespaces }
            "8" { Show-YamlCheckInteractive -CheckIDs "WRK007" -ExcludeNamespaces:$ExcludeNamespaces }
            "9" { Show-YamlCheckInteractive -CheckIDs "WRK008" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }        

    } while ($true)
}



function Show-NodeMenu {
    do {
        Write-Host "`n🔍 Node Details Menu" -ForegroundColor Cyan
        Write-Host "----------------------------------"

        $nodeOptions = @(
            "[1]  List all nodes and node conditions"
            "[2]  Get node resource usage"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $nodeOptions) {
            Write-Host $option
        }

        # Get user choice
        $nodeChoice = Read-Host "`n🤖 Enter a number"
        Clear-Host

        switch ($nodeChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "NODE001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "NODE002" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }  # Back to main menu
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

function show-NamespaceMenu {
    param(
        [switch]$ExcludeNamespaces
    )
    do {
        Write-Host "`n🌐 Namespace Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $namespaceOptions = @(
            "[1]  Show empty namespaces"
            "[2]  Check ResourceQuotas"
            "[3]  Check LimitRanges"
            "🔙  Back (B) | ❌ Exit (Q)"
        )

        foreach ($option in $namespaceOptions) { Write-Host $option }

        $namespaceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($namespaceChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "NS001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "NS002" -ExcludeNamespaces:$ExcludeNamespaces }
            "3" { Show-YamlCheckInteractive -CheckIDs "NS003" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}


# 🚀 Pod Management Menu
function Show-PodMenu {
    do {
        Write-Host "`n🚀 Pod Management Menu" -ForegroundColor Cyan
        Write-Host "--------------------------------`n"

        # Ask for namespace preference
        Write-Host "🤖 Would you like to check:`n" -ForegroundColor Yellow
        Write-Host "   [1] All namespaces 🌍"
        Write-Host "   [2] Choose a specific namespace"
        Write-Host "   🔙 Back [B]"

        $nsChoice = Read-Host "`nEnter choice"
        Clear-Host

        if ($nsChoice -match "^[Bb]$") { return }

        $namespace = ""
        if ($nsChoice -match "^[2]$") {
            do {
                $selectedNamespace = Read-Host "`n🤖 Enter the namespace (or type 'L' to list available ones)"
                Clear-Host
                if ($selectedNamespace -match "^[Ll]$") {
                    Write-Host -NoNewline "`r🤖 Fetching available namespaces..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1  # Optional small delay for UX
                    
                    # Capture namespaces first
                    $namespaces = kubectl get namespaces --no-headers | ForEach-Object { $_.Split()[0] }
                    
                    # Clear previous line and print the list properly
                    Write-Host "`r🤖 Available namespaces fetched.   " -ForegroundColor Green
                    Write-Host "`n🤖 Available Namespaces:`n" -ForegroundColor Cyan
                    $namespaces | ForEach-Object { Write-Host $_ }
                    
                    Write-Host ""
                    $selectedNamespace = ""  # Reset to prompt again
                }
            } until ($selectedNamespace -match "^[a-zA-Z0-9-]+$" -and $selectedNamespace -ne "")

            $namespace = "$selectedNamespace"
        }



        do {
            # Clear screen but keep the "Using namespace" message
            Clear-Host
            Write-Host "`n🤖 Using namespace: " -NoNewline -ForegroundColor Cyan
            Write-Host $(if ($namespace -eq "") { "All Namespaces 🌍" } else { $namespace }) -ForegroundColor Yellow
            Write-Host ""
            Write-Host "📦 Choose a pod operation:`n" -ForegroundColor Cyan

            $podOptions = @(
                "[1]  Show pods with high restarts"
                "[2]  Show long-running pods"
                "[3]  Show failed pods"
                "[4]  Show pending pods"
                "[5]  Show CrashLoopBackOff pods"
                "[6]  Show running debug pods."
                "[7]  Show pods using ':latest' image tag"
                "🔙  Back [B] | ❌ Exit [Q]"
            )

            foreach ($option in $podOptions) { Write-Host $option }

            $podChoice = Read-Host "`n🤖 Enter your choice"
            Clear-Host

            switch ($podChoice) {
                "1" { Show-YamlCheckInteractive -CheckIDs "POD001" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "2" { Show-YamlCheckInteractive -CheckIDs "POD002" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "3" { Show-YamlCheckInteractive -CheckIDs "POD003" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "4" { Show-YamlCheckInteractive -CheckIDs "POD004" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "5" { Show-YamlCheckInteractive -CheckIDs "POD005" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "6" { Show-YamlCheckInteractive -CheckIDs "POD006" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "7" { Show-YamlCheckInteractive -CheckIDs "POD007" -Namespace $Namespace -ExcludeNamespaces:$ExcludeNamespaces }
                "B" { return }
                "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
                default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
            }

            Clear-Host

        } while ($true)

    } while ($true)
}

# 🌐 Service & Networking Menu
function Show-ServiceMenu {
    do {
        Write-Host "`n🌐 Service & Networking Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $serviceOptions = @(
            "[1]  Show services without Endpoints",
            "[2]  Show publicly accessible Services",
            "[3]  Show Ingress configuration issues",
            "[4]  Show namespaces missing NetworkPolicy 🛡️",
            "🔙  Back [B] | ❌ Exit [Q]"
        )


        foreach ($option in $serviceOptions) { Write-Host $option }

        $serviceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($serviceChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "NET001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "NET002" -ExcludeNamespaces:$ExcludeNamespaces }
            "3" { Show-YamlCheckInteractive -CheckIDs "NET003" -ExcludeNamespaces:$ExcludeNamespaces }
            "4" { Show-YamlCheckInteractive -CheckIDs "NET004" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }        

        Clear-Host
    } while ($true)
}

# 📦 Storage Management Menu
function Show-StorageMenu {
    do {
        Write-Host "`n📦 Storage Management Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $storageOptions = @(
            "[1]  Show unused PVCs"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $storageOptions) { Write-Host $option }

        $storageChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($storageChoice) {
            "1" {
                Show-YamlCheckInteractive -CheckIDs "PVC001" -ExcludeNamespaces:$ExcludeNamespaces
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host
    } while ($true)
}

# 🔐 RBAC & Security Menu
function Show-RBACMenu {
    do {
        Write-Host "`n🔐 RBAC & Security Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $rbacOptions = @(
            "[1]  Check RBAC misconfigurations",
            "[2]  Check RBAC overexposure",
            "[3]  Check orphaned Service Accounts",
            "[4]  Show unused Roles & ClusterRoles",
            "[5]  Show orphaned Secrets",
            "[6]  Check Pods running as root",
            "[7]  Check privileged containers",
            "[8]  Check hostPID / hostNetwork usage",
            "[9]  Check hostIPC usage",
            "[10] Check secrets exposed via env vars",
            "[11] Check containers missing 'drop ALL' caps",
            "[12] Check use of hostPath volumes",
            "[13] Check UID 0 containers",
            "[14] Check added Linux capabilities",
            "[15] Check use of emptyDir volumes",
            "[16] Check untrusted image registries",
            "[17] Check use of default ServiceAccount",
            "[18] Check references to missing Secrets",
            "🔙  Back [B] | ❌ Exit [Q]"
        )        

        foreach ($option in $rbacOptions) { Write-Host $option }

        $rbacChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($rbacChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "RBAC001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "RBAC002" -ExcludeNamespaces:$ExcludeNamespaces }
            "3" { Show-YamlCheckInteractive -CheckIDs "RBAC003" -ExcludeNamespaces:$ExcludeNamespaces }
            "4" { Show-YamlCheckInteractive -CheckIDs "RBAC004" -ExcludeNamespaces:$ExcludeNamespaces }
            "5" { Show-YamlCheckInteractive -CheckIDs "SEC001" -ExcludeNamespaces:$ExcludeNamespaces }
            "6" { Show-YamlCheckInteractive -CheckIDs "SEC003" -ExcludeNamespaces:$ExcludeNamespaces }
            "7" { Show-YamlCheckInteractive -CheckIDs "SEC004" -ExcludeNamespaces:$ExcludeNamespaces }
            "8" { Show-YamlCheckInteractive -CheckIDs "SEC002" -ExcludeNamespaces:$ExcludeNamespaces }
            "9" { Show-YamlCheckInteractive -CheckIDs "SEC005" -ExcludeNamespaces:$ExcludeNamespaces }
            "10" { Show-YamlCheckInteractive -CheckIDs "SEC008" -ExcludeNamespaces:$ExcludeNamespaces }
            "11" { Show-YamlCheckInteractive -CheckIDs "SEC009" -ExcludeNamespaces:$ExcludeNamespaces }
            "12" { Show-YamlCheckInteractive -CheckIDs "SEC010" -ExcludeNamespaces:$ExcludeNamespaces }
            "13" { Show-YamlCheckInteractive -CheckIDs "SEC011" -ExcludeNamespaces:$ExcludeNamespaces }
            "14" { Show-YamlCheckInteractive -CheckIDs "SEC012" -ExcludeNamespaces:$ExcludeNamespaces }
            "15" { Show-YamlCheckInteractive -CheckIDs "SEC013" -ExcludeNamespaces:$ExcludeNamespaces }
            "16" { Show-YamlCheckInteractive -CheckIDs "SEC014" -ExcludeNamespaces:$ExcludeNamespaces }
            "17" { Show-YamlCheckInteractive -CheckIDs "SEC015" -ExcludeNamespaces:$ExcludeNamespaces }
            "18" { Show-YamlCheckInteractive -CheckIDs "SEC016" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }
        
        Clear-Host
    } while ($true)
}

# 🏗️ Kubernetes Jobs Menu
function Show-JobsMenu {
    do {
        Write-Host "`n🏢 Kubernetes Jobs Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $jobOptions = @(
            "[1]  Show stuck Kubernetes jobs"
            "[2]  Show failed Kubernetes jobs"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $jobOptions) { Write-Host $option }

        $jobChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($jobChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "JOB001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "JOB002" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

function Show-ConfigMapHygieneMenu {
    param(
        [switch]$ExcludeNamespaces
    )
    do {
        Write-Host "`n🧹 ConfigMap Hygiene Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $cfgOptions = @(
            "[1]  Show orphaned ConfigMaps",
            "[2]  Check for duplicate ConfigMap names",
            "[3]  Check for large ConfigMaps (>1 MiB)",
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $cfgOptions) { Write-Host $option }

        $cfgChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($cfgChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "CFG001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "CFG002" -ExcludeNamespaces:$ExcludeNamespaces }
            "3" { Show-YamlCheckInteractive -CheckIDs "CFG003" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

function Show-KubeEventsMenu {
    param([switch]$ExcludeNamespaces)
    do {
        Write-Host "`n⚠️ Cluster Warning Events" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $eventOptions = @(
            "[1]  Show grouped warning events",
            "[2]  Show full warning event log",
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $eventOptions) { Write-Host $option }

        $eventChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($eventChoice) {
            "1" { Show-YamlCheckInteractive -CheckIDs "EVENT001" -ExcludeNamespaces:$ExcludeNamespaces }
            "2" { Show-YamlCheckInteractive -CheckIDs "EVENT002" -ExcludeNamespaces:$ExcludeNamespaces }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host
    } while ($true)
}


function Show-InfraBestPracticesMenu {
    do {
        Write-Host "`n✅ Infrastructure Best Practices Menu" -ForegroundColor Cyan
        Write-Host "----------------------------------"

        $infraOptions = @(
            "[1]  Run AKS Best Practices Check"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $infraOptions) {
            Write-Host $option
        }

        # Get user choice
        $infraChoice = Read-Host "`n🤖 Enter a number"
        Clear-Host

        switch ($infraChoice) {
            "1" { 
                if (-not $SubscriptionId -or -not $ResourceGroup -or -not $ClusterName) {
                    Write-Host "Parameters are missing. please rerun Invoke-KubeBuddy with the following parameters.`n Invoke-KubeBuddy -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName`n" -ForegroundColor Red
                    Read-Host "Press Enter to return to the main menu"
                    return
                }
                
                Invoke-AKSBestPractices -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
                
            }
            "B" { return }  # Back to main menu
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; return "exit" }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}
