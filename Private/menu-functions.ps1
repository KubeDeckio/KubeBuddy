
function show-mainMenu {
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
            "[10] Cluster Warning Events ⚠️"
            "[Q]  Exit ❌"
        )
    
        foreach ($option in $options) { Write-Host $option }
    
        # Get user choice
        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host
    
        switch ($choice) {
            "1" { Show-ClusterSummary }
            "2" { Show-NodeMenu }
            "3" { Show-NamespaceMenu }
            "4" { Show-WorkloadMenu }
            "5" { Show-PodMenu }
            "6" { Show-JobsMenu }
            "7" { Show-ServiceMenu }
            "8" { Show-StorageMenu }
            "9" { Show-RBACMenu }
            "10" { Show-KubeEvents }
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
            "[1] Check DaemonSet Health 🛠️"
            "[2] Check Deployment Issues 🚀"
            "[3] Check StatefulSet Issues 🏗️"
            "[4] Check ReplicaSet Health 📈"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $options) { Write-Host $option }

        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($choice) {
            "1" { Show-DaemonSetIssues }

            "2" {
                $msg = @(
                    "🤖 Deployment Issues Check is coming soon!",
                    "",
                    "   - This feature will identify failing or unhealthy Deployments, rollout failures, and unavailable pods.",
                    "   - Stay tuned! 🚀"
                )

                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50
                
                Read-Host "🤖 Press Enter to return to the menu"
            }

            "3" {
                $msg = @(
                    "🤖 StatefulSet Health Check is coming soon!",
                    "",
                    "   - This feature will analyze StatefulSets for failures, stuck rollouts, and missing pods.",
                    "   - Stay tuned for updates! 🏗️"
                )

                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50

                Read-Host "🤖 Press Enter to return to the menu"
            }

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

            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
            "1" { 
                Show-NodeConditions
            }
            "2" { 
                Show-NodeResourceUsage
            }
            "B" { return }  # Back to main menu
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

function show-NamespaceMenu {
    do {
        Write-Host "`n🌐 Namespace Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $namespaceOptions = @(
            "[1]  Show empty namespaces"
            "🔙  Back (B) | ❌ Exit (Q)"
        )

        foreach ($option in $namespaceOptions) { Write-Host $option }

        $namespaceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($namespaceChoice) {
            "1" { 
                Show-EmptyNamespaces 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
                    Write-Host -NoNewline "`r🤖 Fetching available namespaces...       ⏳ Fetching..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1  # Optional small delay for UX
                    
                    # Capture namespaces first
                    $namespaces = kubectl get namespaces --no-headers | ForEach-Object { $_.Split()[0] }
                    
                    # Clear previous line and print the list properly
                    Write-Host "`r🤖 Fetching available namespaces...       ✅ Done!" -ForegroundColor Green
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
                "🔙  Back [B] | ❌ Exit [Q]"
            )

            foreach ($option in $podOptions) { Write-Host $option }

            $podChoice = Read-Host "`n🤖 Enter your choice"
            Clear-Host

            switch ($podChoice) {
                "1" { 
                    Show-PodsWithHighRestarts -Namespace $Namespace
                }
                "2" { 
                    Show-LongRunningPods -Namespace $Namespace
                }
                "3" { 
                    Show-FailedPods -Namespace $Namespace
                }
                "4" { 
                    Show-PendingPods -Namespace $Namespace
                }
                "5" {
                    Show-CrashLoopBackOffPods -Namespace $Namespace
                }
                "B" { return }
                "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
            "[1]  Show services without endpoints"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $serviceOptions) { Write-Host $option }

        $serviceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($serviceChoice) {
            "1" { 
                Show-ServicesWithoutEndpoints 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
                Show-UnusedPVCs 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
            "[1]  Check RBAC misconfigurations"
            "[2]  Show orphaned ConfigMaps"
            "[3]  Show orphaned Secrets"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $rbacOptions) { Write-Host $option }

        $rbacChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($rbacChoice) {
            "1" { 
                Check-RBACMisconfigurations 
            }
            "2" { 
                Check-OrphanedConfigMaps
            }
            "3" { 
                Check-OrphanedSecrets 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
            "1" { 
                Show-StuckJobs 
            }
            "2" { 
                Show-FailedJobs 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}
