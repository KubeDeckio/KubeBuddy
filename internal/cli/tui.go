package cli

import (
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/probe"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
	"github.com/manifoldco/promptui"
	"github.com/spf13/cobra"
)

// ─── Menu entry ───────────────────────────────────────────────────────────────

type menuItem struct {
	Label  string
	Action func(opts tuiOpts) // nil = back/exit
	IsBack bool
	IsExit bool
}

func (m menuItem) String() string { return m.Label }

type tuiOpts struct {
	ChecksDir         string
	ExcludeNamespaces bool
}

// ─── Command ──────────────────────────────────────────────────────────────────

func newMenuCommand() *cobra.Command {
	opts := tuiOpts{ChecksDir: "checks/kubernetes"}
	cmd := &cobra.Command{
		Use:     "menu",
		Aliases: []string{"m"},
		Short:   "Launch the interactive KubeBuddy check browser",
		RunE: func(cmd *cobra.Command, args []string) error {
			t := newTUI()
			t.clear()
			t.drawHeader()
			emitBuddyBubble("Welcome to the KubeBuddy interactive check browser. Use arrow keys to navigate.")
			showMainMenu(t, opts)
			t.clear()
			return nil
		},
	}
	cmd.Flags().StringVar(&opts.ChecksDir, "checks-dir", "checks/kubernetes", "Directory containing check YAML files.")
	cmd.Flags().BoolVar(&opts.ExcludeNamespaces, "exclude-namespaces", false, "Exclude configured namespaces.")
	return cmd
}

// ─── Main menu ────────────────────────────────────────────────────────────────

func showMainMenu(t *tui, opts tuiOpts) {
	for {
		t.clear()
		t.drawHeader()
		emitBuddyBubble("What would you like to check?")

		items := []menuItem{
			{Label: "📊  Cluster Summary"},
			{Label: "🖥️  Node Details"},
			{Label: "📂  Namespace Management"},
			{Label: "⚙️  Workload Management"},
			{Label: "🚀  Pod Management"},
			{Label: "🏢  Kubernetes Jobs"},
			{Label: "🌐  Service & Networking"},
			{Label: "📦  Storage Management"},
			{Label: "🔐  RBAC & Security"},
			{Label: "🧹  ConfigMap Hygiene"},
			{Label: "⚠️  Cluster Warning Events"},
			{Label: "✅  Infrastructure Best Practices"},
			{Label: "❌  Exit", IsExit: true},
		}

		idx, err := runMenu("Main Menu", items)
		if err != nil || items[idx].IsExit {
			return
		}

		switch idx {
		case 0:
			showClusterSummary(t, opts)
		case 1:
			showNodeMenu(t, opts)
		case 2:
			showNamespaceMenu(t, opts)
		case 3:
			showWorkloadMenu(t, opts)
		case 4:
			showPodMenu(t, opts)
		case 5:
			showJobsMenu(t, opts)
		case 6:
			showNetworkingMenu(t, opts)
		case 7:
			showStorageMenu(t, opts)
		case 8:
			showSecurityMenu(t, opts)
		case 9:
			showConfigMenu(t, opts)
		case 10:
			showEventsMenu(t, opts)
		case 11:
			showInfraMenu(t, opts)
		}
	}
}

// ─── Section menus ────────────────────────────────────────────────────────────

func showNodeMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🖥️  Node Details", []checkEntry{
		{ID: "NODE001", Label: "Node conditions & status"},
		{ID: "NODE002", Label: "Node resource pressure"},
		{ID: "NODE003", Label: "Pod density per node"},
	})
}

func showNamespaceMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "📂  Namespace Management", []checkEntry{
		{ID: "NS001", Label: "Empty namespaces"},
		{ID: "NS002", Label: "ResourceQuotas missing"},
		{ID: "NS003", Label: "LimitRanges missing"},
		{ID: "NS004", Label: "Default namespace in use"},
	})
}

func showWorkloadMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "⚙️  Workload Management", []checkEntry{
		{ID: "WRK001", Label: "DaemonSet health"},
		{ID: "WRK002", Label: "Deployment issues"},
		{ID: "WRK003", Label: "StatefulSet issues"},
		{ID: "WRK004", Label: "HPA status"},
		{ID: "WRK005", Label: "Missing resource requests & limits"},
		{ID: "WRK006", Label: "Missing or weak PodDisruptionBudgets"},
		{ID: "WRK007", Label: "Containers missing health probes"},
		{ID: "WRK008", Label: "Deployment selectors with no matching pods"},
		{ID: "WRK009", Label: "Deployment / Pod / Service label consistency"},
		{ID: "WRK010", Label: "Deprecated API versions in use"},
		{ID: "WRK011", Label: "Rollout strategy issues"},
		{ID: "WRK012", Label: "Replica spread & anti-affinity"},
		{ID: "WRK013", Label: "Image pull policy issues"},
		{ID: "WRK014", Label: "Resource limits missing (memory only)"},
		{ID: "WRK015", Label: "Max unavailable set to 100%"},
	})
}

func showPodMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🚀  Pod Management", []checkEntry{
		{ID: "POD001", Label: "Pods not running"},
		{ID: "POD002", Label: "Pods with high restart counts"},
		{ID: "POD003", Label: "Long-pending pods"},
		{ID: "POD004", Label: "Pods without owner references"},
		{ID: "POD005", Label: "Pods stuck in terminating"},
		{ID: "POD006", Label: "Pods using host network"},
		{ID: "POD007", Label: "Pods using host PID / IPC"},
		{ID: "POD008", Label: "Pods with no resource limits"},
	})
}

func showJobsMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🏢  Kubernetes Jobs", []checkEntry{
		{ID: "JOB001", Label: "Failed jobs"},
		{ID: "JOB002", Label: "Jobs without deadlines"},
	})
}

func showNetworkingMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🌐  Service & Networking", []checkEntry{
		{ID: "NET001", Label: "Services with no endpoints"},
		{ID: "NET002", Label: "Services with mismatched selectors"},
		{ID: "NET003", Label: "NodePort services exposed"},
		{ID: "NET004", Label: "Services without network policies"},
		{ID: "NET005", Label: "Ingresses with no TLS"},
		{ID: "NET006", Label: "Ingresses pointing to missing services"},
		{ID: "NET007", Label: "LoadBalancer services with open access"},
		{ID: "NET008", Label: "Ingress host conflicts"},
		{ID: "NET009", Label: "Services with no labels"},
		{ID: "NET010", Label: "ExternalName services"},
		{ID: "NET011", Label: "Services with deprecated annotations"},
		{ID: "NET012", Label: "Ingress missing host"},
		{ID: "NET013", Label: "Namespaces without network policy"},
		{ID: "NET014", Label: "Ingress class not set"},
		{ID: "NET015", Label: "Services with multiple ports missing names"},
		{ID: "NET016", Label: "Gateway API: Gateway class missing"},
		{ID: "NET017", Label: "Gateway API: HTTPRoute with no parent"},
		{ID: "NET018", Label: "Gateway API: Cross-namespace reference grants"},
	})
}

func showStorageMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "📦  Storage Management", []checkEntry{
		{ID: "PV001", Label: "PersistentVolumes not bound"},
		{ID: "PVC001", Label: "PersistentVolumeClaims pending"},
		{ID: "PVC002", Label: "PVCs with no storage class"},
		{ID: "PVC003", Label: "PVCs with no access mode set"},
		{ID: "PVC004", Label: "PVCs orphaned from workloads"},
		{ID: "SC001", Label: "StorageClasses with no default"},
		{ID: "SC002", Label: "StorageClass prevents volume expansion"},
		{ID: "SC003", Label: "Pods using in-tree storage provisioners"},
	})
}

func showSecurityMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🔐  RBAC & Security", []checkEntry{
		{ID: "RBAC001", Label: "ClusterRoleBindings with wildcards"},
		{ID: "RBAC002", Label: "RoleBindings with wildcards"},
		{ID: "RBAC003", Label: "ServiceAccounts with excessive RBAC"},
		{ID: "RBAC004", Label: "ClusterAdmin role bound to service accounts"},
		{ID: "SEC001", Label: "Containers running as root"},
		{ID: "SEC002", Label: "Privileged containers"},
		{ID: "SEC003", Label: "Containers with privilege escalation"},
		{ID: "SEC004", Label: "Containers with host path mounts"},
		{ID: "SEC005", Label: "Pods without seccomp profile"},
		{ID: "SEC006", Label: "Pods with writable root filesystem"},
		{ID: "SEC007", Label: "Containers with extra capabilities"},
		{ID: "SEC008", Label: "Containers with NET_ADMIN capability"},
		{ID: "SEC009", Label: "Containers with SYS_ADMIN capability"},
		{ID: "SEC010", Label: "Pods with host ports"},
		{ID: "SEC011", Label: "Pods sharing host IPC"},
		{ID: "SEC012", Label: "Pods sharing host PID"},
		{ID: "SEC013", Label: "Pods sharing host network"},
		{ID: "SEC014", Label: "Secrets mounted as environment variables"},
		{ID: "SEC015", Label: "ServiceAccounts set to default with automount"},
		{ID: "SEC016", Label: "Non-existent secret references"},
		{ID: "SEC017", Label: "Images from untrusted registries"},
		{ID: "SEC018", Label: "ServiceAccounts with automount enabled"},
		{ID: "SEC019", Label: "Unconfined seccomp profiles"},
		{ID: "SEC020", Label: "Disallowed sysctls"},
	})
}

func showConfigMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🧹  ConfigMap Hygiene", []checkEntry{
		{ID: "CFG001", Label: "Unused ConfigMaps"},
		{ID: "CFG002", Label: "ConfigMaps with no data"},
		{ID: "CFG003", Label: "Unused Secrets"},
	})
}

func showEventsMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "⚠️  Cluster Warning Events", []checkEntry{
		{ID: "EVENT001", Label: "Warning events (grouped by reason)"},
		{ID: "EVENT002", Label: "All warning events"},
	})
}

func showInfraMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "✅  Infrastructure Best Practices", []checkEntry{
		{ID: "NODE001", Label: "Node readiness & conditions"},
		{ID: "NODE002", Label: "Node resource pressure"},
		{ID: "NODE003", Label: "Pod density per node"},
		{ID: "WRK005", Label: "Missing resource requests & limits"},
		{ID: "WRK006", Label: "PodDisruptionBudgets"},
		{ID: "WRK007", Label: "Missing health probes"},
		{ID: "NET004", Label: "Missing network policies"},
		{ID: "SEC001", Label: "Containers running as root"},
		{ID: "SEC002", Label: "Privileged containers"},
		{ID: "RBAC001", Label: "RBAC wildcard bindings"},
	})
}

// ─── Generic section menu ─────────────────────────────────────────────────────

type checkEntry struct {
	ID    string
	Label string
}

func showSectionMenu(t *tui, opts tuiOpts, title string, entries []checkEntry) {
	for {
		t.clear()
		t.drawHeader()
		emitBuddyBubble(title)

		items := make([]menuItem, 0, len(entries)+1)
		for _, e := range entries {
			e := e
			items = append(items, menuItem{
				Label: fmt.Sprintf("%-10s  %s", e.ID, e.Label),
				Action: func(o tuiOpts) {
					runSingleCheck(t, o, e.ID, e.Label)
				},
			})
		}
		items = append(items, menuItem{Label: "🔙  Back", IsBack: true})

		idx, err := runMenu(title, items)
		if err != nil || items[idx].IsBack || items[idx].IsExit {
			return
		}
		if items[idx].Action != nil {
			items[idx].Action(opts)
		}
	}
}

// showClusterSummary runs probe + full scan and renders a cluster overview card.
func showClusterSummary(t *tui, opts tuiOpts) {
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Running cluster summary — this may take a moment…")

	probeResult, probeErr := probe.Run()

	result, scanErr := scan.Run(scan.Options{
		ChecksDir:         opts.ChecksDir,
		ExcludeNamespaces: opts.ExcludeNamespaces,
	})

	t.clear()
	t.drawHeader()

	const (
		cyan   = "\x1b[36m"
		green  = "\x1b[32m"
		yellow = "\x1b[33m"
		red    = "\x1b[31m"
		gray   = "\x1b[90m"
		bold   = "\x1b[1m"
		reset  = "\x1b[0m"
	)

	fmt.Printf("\n%s📊 Cluster Summary%s\n", bold, reset)
	fmt.Printf("%s%s%s\n", gray, strings.Repeat("─", 50), reset)

	if probeErr == nil {
		fmt.Printf("  %-20s %s%s%s\n", "Context:", cyan, probeResult.Context, reset)
		fmt.Printf("  %-20s %s%d%s\n", "Nodes:", bold, probeResult.NodeCount, reset)
		fmt.Printf("  %-20s %s%d%s\n", "Pods:", bold, probeResult.PodCount, reset)
		fmt.Printf("  %-20s %s%d%s\n", "Namespaces:", bold, len(probeResult.Namespaces), reset)
	} else {
		fmt.Printf("  %s⚠️  Could not probe cluster: %s%s\n", yellow, probeErr.Error(), reset)
	}

	if scanErr != nil {
		fmt.Printf("\n  %s⚠️  Could not run checks: %s%s\n", yellow, scanErr.Error(), reset)
		fmt.Println()
		pressEnter()
		return
	}

	type failedCheck struct {
		ID, Name, Severity string
		Total              int
	}
	var critical, high, warning, info, passing int
	var failed []failedCheck
	for _, c := range result.Checks {
		if c.Total == 0 {
			passing++
			continue
		}
		failed = append(failed, failedCheck{c.ID, c.Name, c.Severity, c.Total})
		switch strings.ToLower(c.Severity) {
		case "critical":
			critical++
		case "high":
			high++
		case "warning", "medium":
			warning++
		default:
			info++
		}
	}

	fmt.Printf("\n%s  Check Results%s\n", gray, reset)
	fmt.Printf("%s  %s%s\n", gray, strings.Repeat("─", 40), reset)
	fmt.Printf("  %-20s %s%d%s\n", "Total Checks:", bold, len(result.Checks), reset)
	fmt.Printf("  %-20s %s%d%s\n", "Passing:", green, passing, reset)
	fmt.Printf("  %-20s %s%d%s\n", "Failing:", red, len(failed), reset)
	if critical > 0 {
		fmt.Printf("  %-20s %s%d%s\n", "  Critical:", red, critical, reset)
	}
	if high > 0 {
		fmt.Printf("  %-20s %s%d%s\n", "  High:", yellow, high, reset)
	}
	if warning > 0 {
		fmt.Printf("  %-20s %s%d%s\n", "  Warning:", yellow, warning, reset)
	}
	if info > 0 {
		fmt.Printf("  %-20s %s%d%s\n", "  Info:", cyan, info, reset)
	}

	if len(failed) > 0 {
		sort.Slice(failed, func(i, j int) bool {
			return severityWeight(failed[i].Severity) > severityWeight(failed[j].Severity)
		})
		limit := 10
		if len(failed) < limit {
			limit = len(failed)
		}
		fmt.Printf("\n%s  Top Failing Checks%s\n", bold, reset)
		fmt.Printf("%s  %-10s  %-35s  %s%s\n", gray, "ID", "Name", "Issues", reset)
		fmt.Printf("%s  %s%s\n", gray, strings.Repeat("─", 60), reset)
		for _, f := range failed[:limit] {
			sColor := severityColor(f.Severity)
			fmt.Printf("  %s%-10s%s  %-35s  %s%d%s\n",
				sColor, f.ID, reset, truncate(f.Name, 35), yellow, f.Total, reset)
		}
	}

	fmt.Println()
	pressEnter()
}

// ─── Single-check runner ──────────────────────────────────────────────────────

const pageSize = 20

func runSingleCheck(t *tui, opts tuiOpts, checkID, label string) {
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Running " + checkID + " — " + label + "…")

	result, err := scan.Run(scan.Options{
		ChecksDir:         opts.ChecksDir,
		ExcludeNamespaces: opts.ExcludeNamespaces,
	})
	if err != nil {
		emitBuddyBubble("Error running check: " + err.Error())
		pressEnter()
		return
	}

	var found *scan.CheckResult
	for i := range result.Checks {
		if result.Checks[i].ID == checkID {
			found = &result.Checks[i]
			break
		}
	}

	if found == nil {
		emitBuddyBubble("Check " + checkID + " not found in the catalog.")
		pressEnter()
		return
	}

	showCheckResult(t, *found)
}

func showCheckResult(t *tui, result scan.CheckResult) {
	t.clear()
	t.drawHeader()

	const (
		cyan   = "\x1b[36m"
		green  = "\x1b[32m"
		yellow = "\x1b[33m"
		red    = "\x1b[31m"
		gray   = "\x1b[90m"
		bold   = "\x1b[1m"
		reset  = "\x1b[0m"
	)

	// Summary card
	statusIcon := green + "✅ PASS" + reset
	if result.Total > 0 {
		statusIcon = red + "❌ FAIL" + reset
	}
	fmt.Printf("\n%s%s — %s%s\n", bold, result.ID, result.Name, reset)
	fmt.Printf("%s─────────────────────────────────────────%s\n", gray, reset)
	fmt.Printf("  Status   : %s\n", statusIcon)
	fmt.Printf("  Severity : %s%s%s\n", severityColor(result.Severity), result.Severity, reset)
	if result.Total > 0 {
		fmt.Printf("  Findings : %s%d%s\n", yellow, result.Total, reset)
	}
	if strings.TrimSpace(result.Description) != "" {
		fmt.Printf("  %s%s%s\n", gray, result.Description, reset)
	}
	fmt.Println()

	if result.Total == 0 {
		emitBuddyBubble("No issues found for " + result.ID + ". Great work!")
		pressEnter()
		return
	}

	// Speech bubble with recommendation
	if strings.TrimSpace(result.Recommendation) != "" {
		emitBuddyBubble("Recommendation: " + result.Recommendation)
	}

	// Paginated findings table
	items := result.Items
	totalPages := (len(items) + pageSize - 1) / pageSize
	page := 0

	for {
		start := page * pageSize
		end := start + pageSize
		if end > len(items) {
			end = len(items)
		}

		fmt.Printf("%s  Findings — page %d of %d  (showing %d–%d of %d)%s\n",
			cyan, page+1, totalPages, start+1, end, len(items), reset)
		fmt.Printf("%s  %-30s  %-30s  %-20s  %s%s\n",
			gray, "Namespace", "Resource", "Value", "Message", reset)
		fmt.Printf("%s  %s%s\n", gray, strings.Repeat("─", 110), reset)

		for _, item := range items[start:end] {
			ns := truncate(item.Namespace, 30)
			res := truncate(item.Resource, 30)
			val := truncate(item.Value, 20)
			msg := truncate(item.Message, 50)
			fmt.Printf("  %-30s  %-30s  %-20s  %s\n", ns, res, val, msg)
		}
		fmt.Println()

		// Navigation
		navItems := []string{}
		if page > 0 {
			navItems = append(navItems, "← Previous")
		}
		if page < totalPages-1 {
			navItems = append(navItems, "Next →")
		}
		navItems = append(navItems, "🔙 Back to menu")

		choice, err := rawSelect("Navigate", navItems)
		if err != nil || choice == "🔙 Back to menu" {
			break
		}
		if choice == "← Previous" {
			page--
		} else {
			page++
		}
		t.clear()
		t.drawHeader()
	}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func runMenu(label string, items []menuItem) (int, error) {
	prompt := promptui.Select{
		Label:     label,
		Items:     items,
		Size:      min(len(items), 15),
		HideHelp:  true,
		Templates: selectTemplates(),
	}
	idx, _, err := prompt.Run()
	return idx, err
}

func pressEnter() {
	fmt.Print("\n  Press Enter to continue...")
	buf := make([]byte, 1)
	os.Stdin.Read(buf) //nolint:errcheck
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-1] + "…"
}

func severityColor(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "critical", "high":
		return "\x1b[31m"
	case "warning", "medium":
		return "\x1b[33m"
	default:
		return "\x1b[36m"
	}
}

func severityWeight(s string) int {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "critical":
		return 4
	case "high":
		return 3
	case "warning", "medium":
		return 2
	default:
		return 1
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
