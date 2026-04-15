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
	Label    string
	Shortcut string
	Action   func(opts tuiOpts) // nil = back/exit
	IsBack   bool
	IsExit   bool
}

func (m menuItem) String() string {
	if strings.TrimSpace(m.Shortcut) == "" {
		return m.Label
	}
	return fmt.Sprintf("[%s] %s", m.Shortcut, m.Label)
}

type tuiOpts struct {
	ChecksDir         string
	ExcludeNamespaces bool
	ConfigPath        string
	SubscriptionID    string
	ResourceGroup     string
	ClusterName       string
}

// ─── Command ──────────────────────────────────────────────────────────────────

func newMenuCommand() *cobra.Command {
	opts := tuiOpts{ChecksDir: "checks/kubernetes"}
	cmd := &cobra.Command{
		Use:     "menu",
		Aliases: []string{"m"},
		Short:   "Launch the interactive KubeBuddy check browser",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runInteractiveBrowser(opts)
		},
		Hidden: true,
	}
	cmd.Flags().StringVar(&opts.ChecksDir, "checks-dir", "checks/kubernetes", "Directory containing check YAML files.")
	cmd.Flags().BoolVar(&opts.ExcludeNamespaces, "exclude-namespaces", false, "Exclude configured namespaces.")
	cmd.Flags().StringVar(&opts.ConfigPath, "config-path", "", "KubeBuddy config file path.")
	cmd.Flags().StringVar(&opts.SubscriptionID, "subscription-id", "", "AKS subscription ID for infrastructure checks.")
	cmd.Flags().StringVar(&opts.ResourceGroup, "resource-group", "", "AKS resource group for infrastructure checks.")
	cmd.Flags().StringVar(&opts.ClusterName, "cluster-name", "", "AKS cluster name for infrastructure checks.")
	return cmd
}

func newTUICommand() *cobra.Command {
	opts := tuiOpts{ChecksDir: "checks/kubernetes"}
	cmd := &cobra.Command{
		Use:   "tui",
		Short: "Launch the interactive KubeBuddy terminal UI",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runTUIHome(opts)
		},
	}
	cmd.Flags().StringVar(&opts.ChecksDir, "checks-dir", "checks/kubernetes", "Directory containing check YAML files.")
	cmd.Flags().BoolVar(&opts.ExcludeNamespaces, "exclude-namespaces", false, "Exclude configured namespaces.")
	cmd.Flags().StringVar(&opts.ConfigPath, "config-path", "", "KubeBuddy config file path.")
	cmd.Flags().StringVar(&opts.SubscriptionID, "subscription-id", "", "AKS subscription ID for infrastructure checks.")
	cmd.Flags().StringVar(&opts.ResourceGroup, "resource-group", "", "AKS resource group for infrastructure checks.")
	cmd.Flags().StringVar(&opts.ClusterName, "cluster-name", "", "AKS cluster name for infrastructure checks.")
	return cmd
}

func runTUIHome(opts tuiOpts) error {
	t := newTUI()
	for {
		t.clear()
		t.drawHeader()
		emitBuddyBubble("Choose a workflow. Use arrow keys, or type a shortcut and press Enter.")

		items := []menuItem{
			{Label: "Guided report workflow", Shortcut: "g"},
			{Label: "Interactive check browser", Shortcut: "c"},
			{Label: "Exit", Shortcut: "q", IsExit: true},
		}

		idx, err := runMenu("KubeBuddy TUI", items)
		if err != nil || items[idx].IsExit {
			t.clear()
			return nil
		}

		switch items[idx].Shortcut {
		case "g":
			if err := runGuidedFlow(); err != nil {
				return err
			}
		case "c":
			if err := runInteractiveBrowser(opts); err != nil {
				return err
			}
		}
	}
}

func runInteractiveBrowser(opts tuiOpts) error {
	t := newTUI()
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Welcome to the KubeBuddy interactive check browser. Use arrow keys, or type a shortcut and press Enter.")
	showMainMenu(t, opts)
	t.clear()
	return nil
}

// ─── Main menu ────────────────────────────────────────────────────────────────

func showMainMenu(t *tui, opts tuiOpts) {
	for {
		t.clear()
		t.drawHeader()
		emitBuddyBubble("What would you like to check?")

		items := []menuItem{
			{Label: "📊  Cluster Summary", Shortcut: "1"},
			{Label: "🖥️  Node Details", Shortcut: "2"},
			{Label: "📂  Namespace Management", Shortcut: "3"},
			{Label: "⚙️  Workload Management", Shortcut: "4"},
			{Label: "🚀  Pod Management", Shortcut: "5"},
			{Label: "🏢  Kubernetes Jobs", Shortcut: "6"},
			{Label: "🌐  Service & Networking", Shortcut: "7"},
			{Label: "📦  Storage Management", Shortcut: "8"},
			{Label: "🔐  RBAC & Security", Shortcut: "9"},
			{Label: "🧹  ConfigMap Hygiene", Shortcut: "a"},
			{Label: "⚠️  Cluster Warning Events", Shortcut: "b"},
			{Label: "✅  Infrastructure Best Practices", Shortcut: "i"},
			{Label: "❌  Exit", Shortcut: "q", IsExit: true},
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
		{ID: "NODE001", Label: "List all nodes and node conditions"},
		{ID: "NODE002", Label: "Get node resource usage"},
		{ID: "NODE003", Label: "Check pod density per node 📦"},
	})
}

func showNamespaceMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "📂  Namespace Management", []checkEntry{
		{ID: "NS001", Label: "Show empty namespaces"},
		{ID: "NS002", Label: "Check ResourceQuotas"},
		{ID: "NS003", Label: "Check LimitRanges"},
	})
}

func showWorkloadMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "⚙️  Workload Management", []checkEntry{
		{ID: "WRK001", Label: "Check DaemonSet Health 🛠️"},
		{ID: "WRK002", Label: "Check Deployment Issues 🚀"},
		{ID: "WRK003", Label: "Check StatefulSet Issues 🏗️"},
		{ID: "WRK004", Label: "Check HPA Status ⚖️"},
		{ID: "WRK005", Label: "Check Missing Resources & Limits 🛟"},
		{ID: "WRK006", Label: "Check missing or weak PodDisruptionBudgets 🛡️"},
		{ID: "WRK007", Label: "Check containers missing health probes 🔎"},
		{ID: "WRK008", Label: "Check Deployment selectors with no matching pods ❌"},
		{ID: "WRK009", Label: "Check Deployment/Pod/Service label consistency 🧩"},
	})
}

func showPodMenu(t *tui, opts tuiOpts) {
	namespace, ok := choosePodNamespace(t)
	if !ok {
		return
	}
	showSectionMenuWithNamespace(t, opts, "🚀  Pod Management", namespace, []checkEntry{
		{ID: "POD001", Label: "Show pods with high restarts"},
		{ID: "POD002", Label: "Show long-running pods"},
		{ID: "POD003", Label: "Show failed pods"},
		{ID: "POD004", Label: "Show pending pods"},
		{ID: "POD005", Label: "Show CrashLoopBackOff pods"},
		{ID: "POD006", Label: "Show running debug pods"},
		{ID: "POD007", Label: "Show pods using ':latest' image tag"},
	})
}

func showJobsMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🏢  Kubernetes Jobs", []checkEntry{
		{ID: "JOB001", Label: "Show stuck Kubernetes jobs"},
		{ID: "JOB002", Label: "Show failed Kubernetes jobs"},
	})
}

func showNetworkingMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🌐  Service & Networking", []checkEntry{
		{ID: "NET001", Label: "Show services without Endpoints"},
		{ID: "NET002", Label: "Show publicly accessible Services"},
		{ID: "NET003", Label: "Show Ingress configuration issues"},
		{ID: "NET004", Label: "Show namespaces missing NetworkPolicy 🛡️"},
		{ID: "NET005", Label: "Check for Ingress host/path conflicts 🚧"},
		{ID: "NET006", Label: "Check Ingress wildcard host usage 🌐"},
		{ID: "NET007", Label: "Check Service targetPort mismatch 🔁"},
		{ID: "NET008", Label: "Check ExternalName services pointing to internal IPs 🌩️"},
		{ID: "NET009", Label: "Check overly permissive NetworkPolicies ⚠️"},
		{ID: "NET010", Label: "Check NetworkPolicies using 0.0.0.0/0 🔓"},
		{ID: "NET011", Label: "Check NetworkPolicies missing policyTypes ❔"},
		{ID: "NET012", Label: "Check pods using hostNetwork 🌐"},
	})
}

func showStorageMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "📦  Storage Management", []checkEntry{
		{ID: "PV001", Label: "Show orphaned PersistentVolumes 🗃️"},
		{ID: "PVC002", Label: "Show PVCs using default StorageClass 🏷️"},
		{ID: "PVC003", Label: "Show ReadWriteMany PVCs on incompatible storage 🔒"},
		{ID: "PVC004", Label: "Show unbound PersistentVolumeClaims ⛔"},
		{ID: "SC001", Label: "Show deprecated StorageClass provisioners 📉"},
		{ID: "SC002", Label: "Show StorageClasses that prevent volume expansion 🚫"},
		{ID: "SC003", Label: "Check high cluster-wide storage usage 📊"},
	})
}

func showSecurityMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🔐  RBAC & Security", []checkEntry{
		{ID: "RBAC001", Label: "Check RBAC misconfigurations"},
		{ID: "RBAC002", Label: "Check RBAC overexposure"},
		{ID: "RBAC003", Label: "Check orphaned Service Accounts"},
		{ID: "RBAC004", Label: "Show unused Roles & ClusterRoles"},
		{ID: "SEC001", Label: "Show orphaned Secrets"},
		{ID: "SEC003", Label: "Check Pods running as root"},
		{ID: "SEC004", Label: "Check privileged containers"},
		{ID: "SEC002", Label: "Check hostPID / hostNetwork usage"},
		{ID: "SEC005", Label: "Check hostIPC usage"},
		{ID: "SEC008", Label: "Check secrets exposed via env vars"},
		{ID: "SEC009", Label: "Check containers missing 'drop ALL' caps"},
		{ID: "SEC010", Label: "Check use of hostPath volumes"},
		{ID: "SEC011", Label: "Check UID 0 containers"},
		{ID: "SEC012", Label: "Check added Linux capabilities"},
		{ID: "SEC013", Label: "Check use of emptyDir volumes"},
		{ID: "SEC014", Label: "Check untrusted image registries"},
		{ID: "SEC015", Label: "Check use of default ServiceAccount"},
		{ID: "SEC016", Label: "Check references to missing Secrets"},
	})
}

func showConfigMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "🧹  ConfigMap Hygiene", []checkEntry{
		{ID: "CFG001", Label: "Show orphaned ConfigMaps"},
		{ID: "CFG002", Label: "Check for duplicate ConfigMap names"},
		{ID: "CFG003", Label: "Check for large ConfigMaps (>1 MiB)"},
	})
}

func showEventsMenu(t *tui, opts tuiOpts) {
	showSectionMenu(t, opts, "⚠️  Cluster Warning Events", []checkEntry{
		{ID: "EVENT001", Label: "Show grouped warning events"},
		{ID: "EVENT002", Label: "Show full warning event log"},
	})
}

func showInfraMenu(t *tui, opts tuiOpts) {
	for {
		t.clear()
		t.drawHeader()
		emitBuddyBubble("Infrastructure Best Practices")

		items := []menuItem{
			{
				Label:    "AKS Best Practices Check",
				Shortcut: "1",
				Action: func(o tuiOpts) {
					runAKSBestPractices(t, o)
				},
			},
			{Label: "🔙  Back", Shortcut: "q", IsBack: true},
		}

		idx, err := runMenu("Infrastructure Best Practices", items)
		if err != nil || items[idx].IsBack {
			return
		}
		if items[idx].Action != nil {
			items[idx].Action(opts)
		}
	}
}

// ─── Generic section menu ─────────────────────────────────────────────────────

type checkEntry struct {
	ID    string
	Label string
}

func showSectionMenu(t *tui, opts tuiOpts, title string, entries []checkEntry) {
	showSectionMenuWithNamespace(t, opts, title, "", entries)
}

func showSectionMenuWithNamespace(t *tui, opts tuiOpts, title string, namespace string, entries []checkEntry) {
	for {
		t.clear()
		t.drawHeader()
		message := title
		if namespace != "" {
			message += " — namespace: " + namespace
		}
		emitBuddyBubble(message)

		items := make([]menuItem, 0, len(entries)+1)
		for _, e := range entries {
			e := e
			items = append(items, menuItem{
				Label:    fmt.Sprintf("%-10s  %s", e.ID, e.Label),
				Shortcut: strings.ToLower(e.ID),
				Action: func(o tuiOpts) {
					runSingleCheck(t, o, e.ID, e.Label, namespace)
				},
			})
		}
		items = append(items, menuItem{Label: "🔙  Back", Shortcut: "q", IsBack: true})

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
		ConfigPath:        opts.ConfigPath,
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
		waitForEnter()
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
	waitForEnter()
}

// ─── Single-check runner ──────────────────────────────────────────────────────

const pageSize = 20

func runSingleCheck(t *tui, opts tuiOpts, checkID, label string, namespace string) {
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Running " + checkID + " — " + label + "…")

	result, err := scan.Run(scan.Options{
		ChecksDir:         opts.ChecksDir,
		ExcludeNamespaces: opts.ExcludeNamespaces,
		ConfigPath:        opts.ConfigPath,
	})
	if err != nil {
		emitBuddyBubble("Error running check: " + err.Error())
		waitForEnter()
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
		waitForEnter()
		return
	}

	if namespace != "" {
		filtered := *found
		items := make([]scan.Finding, 0, len(found.Items))
		for _, item := range found.Items {
			if strings.EqualFold(strings.TrimSpace(item.Namespace), strings.TrimSpace(namespace)) {
				items = append(items, item)
			}
		}
		filtered.Items = items
		filtered.Total = len(items)
		showCheckResult(t, filtered)
		return
	}

	showCheckResult(t, *found)
}

func runAKSBestPractices(t *tui, opts tuiOpts) {
	subscriptionID := strings.TrimSpace(opts.SubscriptionID)
	resourceGroup := strings.TrimSpace(opts.ResourceGroup)
	clusterName := strings.TrimSpace(opts.ClusterName)

	var err error
	if subscriptionID == "" {
		t.step("Enter your Azure Subscription ID.")
		subscriptionID, err = rawInput("Subscription ID", "")
		if err != nil {
			return
		}
	}
	if resourceGroup == "" {
		t.step("Enter the AKS Resource Group.")
		resourceGroup, err = rawInput("Resource Group", "")
		if err != nil {
			return
		}
	}
	if clusterName == "" {
		t.step("Enter the AKS Cluster Name.")
		clusterName, err = rawInput("Cluster Name", "")
		if err != nil {
			return
		}
	}

	t.clear()
	t.drawHeader()
	emitBuddyBubble("Running AKS Best Practices Check…")

	result, err := scan.RunAKS(scan.AKSOptions{
		ChecksDir:      "checks/aks",
		ConfigPath:     opts.ConfigPath,
		SubscriptionID: subscriptionID,
		ResourceGroup:  resourceGroup,
		ClusterName:    clusterName,
	})
	if err != nil {
		emitBuddyBubble("Error running AKS checks: " + err.Error())
		waitForEnter()
		return
	}

	showAKSResults(t, clusterName, result)
}

func showAKSResults(t *tui, clusterName string, result scan.Result) {
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

	passed := 0
	failed := 0
	for _, check := range result.Checks {
		if check.Total == 0 {
			passed++
		} else {
			failed++
		}
	}

	fmt.Printf("\n%sAKS Best Practices — %s%s\n", bold, clusterName, reset)
	fmt.Printf("%s%s%s\n", gray, strings.Repeat("─", 60), reset)
	fmt.Printf("  %-20s %s%d%s\n", "Total Checks:", bold, len(result.Checks), reset)
	fmt.Printf("  %-20s %s%d%s\n", "Passed:", green, passed, reset)
	fmt.Printf("  %-20s %s%d%s\n", "Failed:", red, failed, reset)
	fmt.Println()

	grouped := map[string][]scan.CheckResult{}
	var categories []string
	for _, check := range result.Checks {
		category := strings.TrimSpace(check.Category)
		if category == "" {
			category = "Other"
		}
		if _, ok := grouped[category]; !ok {
			categories = append(categories, category)
		}
		grouped[category] = append(grouped[category], check)
	}
	sort.Strings(categories)

	for _, category := range categories {
		checks := grouped[category]
		categoryFailed := 0
		for _, check := range checks {
			if check.Total > 0 {
				categoryFailed++
			}
		}
		color := green
		if categoryFailed > 0 {
			color = yellow
		}
		fmt.Printf("%s%s%s — %d/%d failed\n", color, category, reset, categoryFailed, len(checks))
		for _, check := range checks {
			status := green + "PASS" + reset
			if check.Total > 0 {
				status = red + "FAIL" + reset
			}
			fmt.Printf("  %-10s %-4s %s\n", check.ID, status, check.Name)
		}
		fmt.Println()
	}

	waitForEnter()
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
		waitForEnter()
		return
	}

	// Prefer the shorter Buddy variant when available.
	if len(result.SpeechBubble) > 0 {
		emitBuddyBubble(strings.Join(result.SpeechBubble, "\n"))
	} else if strings.TrimSpace(result.Recommendation) != "" {
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
		Label:             label + " (↑/↓ to move, type shortcut then Enter)",
		Items:             items,
		Size:              min(len(items), 15),
		HideHelp:          true,
		Templates:         selectTemplates(),
		StartInSearchMode: true,
		Searcher: func(input string, index int) bool {
			input = strings.ToLower(strings.TrimSpace(input))
			if input == "" {
				return true
			}
			item := items[index]
			return strings.Contains(strings.ToLower(item.Shortcut), input) ||
				strings.Contains(strings.ToLower(item.Label), input)
		},
	}
	idx, _, err := prompt.Run()
	return idx, err
}

func waitForEnter() {
	fmt.Print("\n  Press Enter to continue...")
	buf := make([]byte, 1)
	os.Stdin.Read(buf) //nolint:errcheck
}

func choosePodNamespace(t *tui) (string, bool) {
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Would you like to check all namespaces or choose a specific namespace?")

	items := []string{"All namespaces 🌍", "Choose a specific namespace", "🔙  Back"}
	choice, err := rawSelect("Namespace scope", items)
	if err != nil || choice == "🔙  Back" {
		return "", false
	}
	if choice == "All namespaces 🌍" {
		return "", true
	}

	t.step("Enter the namespace you want to inspect.")
	namespace, err := rawInput("Namespace", "")
	if err != nil || strings.TrimSpace(namespace) == "" {
		return "", false
	}
	return strings.TrimSpace(namespace), true
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
