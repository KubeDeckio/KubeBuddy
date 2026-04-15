package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/runner"
	"github.com/manifoldco/promptui"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

// ─── TUI state ────────────────────────────────────────────────────────────────

type tui struct {
	choices []string // running log of confirmed values
	drawn   bool
}

func newTUI() *tui { return &tui{} }

// clear wipes the terminal using ANSI escape codes.
func (t *tui) clear() { fmt.Print("\033[2J\033[H") }

// record appends a confirmed choice to the summary strip.
func (t *tui) record(label string) { t.choices = append(t.choices, label) }

// step clears the screen and redraws the header + choices summary, then
// prints a buddy bubble with the question for the coming prompt.
func (t *tui) step(question string) {
	t.clear()
	t.drawHeader()
	t.drawChoices()
	emitBuddyBubble(question)
}

func (t *tui) drawHeader() {
	const (
		brightCyan = "\033[1;38;5;45m"
		cyan       = "\033[38;5;45m"
		reset      = "\x1b[0m"
	)
	lines := []string{
		"██╗  ██╗██╗   ██║██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗",
		"██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝",
		"█████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║██║  ██║██║  ██║ ╚████╔╝ ",
		"██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║  ██║██║  ██║  ╚██╔╝  ",
		"██║  ██╗╚██████╔╝██████╔╝███████╗██████╔╝╚██████╔╝██████╔╝██████╔╝   ██║   ",
		"╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝    ╚═╝   ",
	}
	fmt.Println()
	if !t.drawn {
		reveals := []float64{0.10, 0.18, 0.28, 0.40, 0.54, 0.68, 0.79, 0.87, 0.93, 0.97, 1.0}
		for frameIdx, ratio := range reveals {
			if frameIdx > 0 {
				fmt.Printf("\033[%dA", len(lines))
			}
			for i, line := range lines {
				color := brightCyan
				if i >= len(lines)-2 {
					color = cyan
				}
				fmt.Println(color + wipeBannerLine(line, ratio) + reset)
			}
			time.Sleep(22 * time.Millisecond)
		}
		sweepColors := []string{cyan, "\033[38;5;51m", brightCyan}
		for sweepIdx, color := range sweepColors {
			fmt.Printf("\033[%dA", len(lines))
			for i, line := range lines {
				lineColor := color
				if i < len(lines)-2 && sweepIdx == 0 {
					lineColor = "\033[38;5;39m"
				}
				fmt.Println(lineColor + line + reset)
			}
			time.Sleep(18 * time.Millisecond)
		}
	} else {
		for i, line := range lines {
			color := brightCyan
			if i >= len(lines)-2 {
				color = cyan
			}
			fmt.Println(color + line + reset)
		}
	}
	fmt.Println()
	t.drawn = true
}

func swipeBannerLine(line string, offset int) string {
	if offset <= 0 {
		return line
	}
	return strings.Repeat(" ", offset) + line
}

func wipeBannerLine(line string, ratio float64) string {
	if ratio >= 1 {
		return line
	}
	if ratio <= 0 {
		return strings.Repeat(" ", len([]rune(line)))
	}
	runes := []rune(line)
	reveal := int(float64(len(runes)) * ratio)
	if reveal < 0 {
		reveal = 0
	}
	if reveal > len(runes) {
		reveal = len(runes)
	}
	return string(runes[:reveal]) + strings.Repeat(" ", len(runes)-reveal)
}

func (t *tui) drawChoices() {
	if len(t.choices) == 0 {
		return
	}
	const (
		gray  = "\x1b[90m"
		green = "\x1b[32m"
		reset = "\x1b[0m"
	)
	fmt.Println(gray + "  Configured so far:" + reset)
	for _, c := range t.choices {
		fmt.Println(green + "  ✓ " + reset + c)
	}
	fmt.Println()
}

// ─── Command ──────────────────────────────────────────────────────────────────

type guidedChoice struct {
	Label string
	Run   func() error
}

func (c guidedChoice) String() string { return c.Label }

func newGuidedCommand() *cobra.Command {
	return &cobra.Command{
		Use:     "guided",
		Aliases: []string{"buddy"},
		Short:   "Launch the guided Buddy workflow",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runGuidedFlow()
		},
		Hidden: true,
	}
}

func runGuidedFlow() error {
	t := newTUI()
	t.clear()
	t.drawHeader()
	emitBuddyBubble("Welcome! I'll guide you through setting up and running a KubeBuddy report.")

	choice, err := rawSelect("What would you like KubeBuddy to do?", []guidedChoice{
		{
			Label: "Generate a Kubernetes report",
			Run: func() error {
				opts, err := buildGuidedRunOptions(t, false)
				if err != nil {
					return err
				}
				return runner.Execute(opts)
			},
		},
		{
			Label: "Generate an AKS report",
			Run: func() error {
				opts, err := buildGuidedRunOptions(t, true)
				if err != nil {
					return err
				}
				return runner.Execute(opts)
			},
		},
		{Label: "Exit"},
	})
	if err != nil {
		return err
	}
	if choice.Run == nil {
		t.clear()
		return nil
	}
	return choice.Run()
}

// ─── Guided flow ──────────────────────────────────────────────────────────────

func buildGuidedRunOptions(t *tui, aks bool) (compat.RunOptions, error) {
	opts := compat.RunOptions{
		Yes:        true,
		OutputPath: defaultGuidedOutputPath(),
	}
	var err error

	// Step — report format
	t.step("Which report format would you like to generate?")
	formatPreset, err := rawSelect("Report format", []string{
		"HTML report",
		"HTML + JSON reports",
		"All report formats",
		"JSON report",
	})
	if err != nil {
		return opts, err
	}
	applyFormatPreset(&opts, formatPreset)
	t.record("Format: " + formatPreset)

	// Step — Prometheus
	t.step("Would you like to include Prometheus checks and metrics?")
	usePrometheus, err := yesNo()
	if err != nil {
		return opts, err
	}
	if usePrometheus {
		opts.IncludePrometheus = true
		t.record("Prometheus: enabled")

		t.step("Enter your Prometheus URL.")
		opts.PrometheusURL, err = rawInput("Prometheus URL", "")
		if err != nil {
			return opts, err
		}
		t.record("Prometheus URL: " + opts.PrometheusURL)

		t.step("How should Prometheus authenticate?")
		mode, err := rawSelect("Authentication mode", []string{"azure", "bearer", "basic", "local"})
		if err != nil {
			return opts, err
		}
		opts.PrometheusMode = mode
		t.record("Prometheus auth: " + mode)

		if mode == "bearer" {
			t.step("Enter the name of the environment variable holding your Prometheus bearer token.")
			opts.PrometheusBearerTokenEnv, err = rawInput("Bearer token env var", "PROMETHEUS_TOKEN")
			if err != nil {
				return opts, err
			}
			t.record("Bearer env: " + opts.PrometheusBearerTokenEnv)
		}
	} else {
		t.record("Prometheus: skipped")
	}

	// Step — namespace exclusion
	t.step("Apply configured excluded namespaces?")
	opts.ExcludeNamespaces, err = yesNo()
	if err != nil {
		return opts, err
	}
	if opts.ExcludeNamespaces {
		t.record("Exclude namespaces: yes")
	} else {
		t.record("Exclude namespaces: no")
	}

	// Step — output directory
	t.step("Where should the reports be saved?")
	opts.OutputPath, err = rawInput("Output directory", opts.OutputPath)
	if err != nil {
		return opts, err
	}
	t.record("Output: " + opts.OutputPath)

	// AKS-specific steps
	if aks {
		opts.AKS = true

		t.step("Enter your Azure Subscription ID.")
		opts.SubscriptionID, err = rawInput("Subscription ID", strings.TrimSpace(os.Getenv("AZURE_SUBSCRIPTION_ID")))
		if err != nil {
			return opts, err
		}
		t.record("Subscription: " + opts.SubscriptionID)

		t.step("Enter the AKS Resource Group name.")
		opts.ResourceGroup, err = rawInput("Resource Group", "")
		if err != nil {
			return opts, err
		}
		t.record("Resource Group: " + opts.ResourceGroup)

		t.step("Enter the AKS Cluster Name.")
		opts.ClusterName, err = rawInput("Cluster Name", "")
		if err != nil {
			return opts, err
		}
		t.record("Cluster: " + opts.ClusterName)
	}

	// Final summary screen
	t.clear()
	t.drawHeader()
	t.drawChoices()
	emitBuddyBubble("All set! Starting the run now...")
	return opts, nil
}

// ─── Low-level prompt helpers ─────────────────────────────────────────────────

func rawSelect[T any](label string, items []T) (T, error) {
	var zero T
	prompt := promptui.Select{
		Label:     label,
		Items:     items,
		Size:      len(items),
		HideHelp:  true,
		Templates: selectTemplates(),
	}
	index, _, err := prompt.Run()
	if err != nil {
		return zero, err
	}
	return items[index], nil
}

func rawInput(label string, defaultValue string) (string, error) {
	prompt := promptui.Prompt{
		Label:     label,
		Default:   defaultValue,
		AllowEdit: true,
		Templates: inputTemplates(),
	}
	value, err := prompt.Run()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(value), nil
}

func yesNo() (bool, error) {
	selected, err := rawSelect("", []string{"Yes", "No"})
	if err != nil {
		return false, err
	}
	return selected == "Yes", nil
}

// ─── Bubble renderer ──────────────────────────────────────────────────────────

func emitBuddyBubble(message string) {
	message = strings.TrimSpace(message)
	if message == "" {
		return
	}
	const (
		cyan  = "\x1b[36m"
		reset = "\x1b[0m"
	)
	maxWidth := tuiTermWidth() - 14 // indent (6) + "| " + " |" + safety margin
	if maxWidth < 20 {
		maxWidth = 60
	}
	lines := wrapLines(message, maxWidth)
	width := 0
	for _, line := range lines {
		if len(line) > width {
			width = len(line)
		}
	}
	border := strings.Repeat("─", width+2)

	fmt.Println()
	fmt.Println(cyan + "      ╭" + border + "╮" + reset)
	for _, line := range lines {
		fmt.Printf("%s      │ %-*s │%s\n", cyan, width, line, reset)
	}
	fmt.Println(cyan + "      ╰" + border + "╯" + reset)
	fmt.Println(cyan + `             ╲` + reset)
	fmt.Println(cyan + `              ╲  🤖  KubeBuddy` + reset)
	fmt.Println()
}

// ─── Utilities ────────────────────────────────────────────────────────────────

func tuiTermWidth() int {
	if w, _, err := term.GetSize(int(os.Stdout.Fd())); err == nil && w > 20 {
		return w
	}
	return 80
}

func wrapLines(message string, width int) []string {
	words := strings.Fields(message)
	if len(words) == 0 {
		return []string{""}
	}
	var lines []string
	current := words[0]
	for _, word := range words[1:] {
		if len(current)+1+len(word) > width {
			lines = append(lines, current)
			current = word
			continue
		}
		current += " " + word
	}
	return append(lines, current)
}

func applyFormatPreset(opts *compat.RunOptions, preset string) {
	switch preset {
	case "HTML report":
		opts.HTMLReport = true
	case "HTML + JSON reports":
		opts.HTMLReport = true
		opts.JSONReport = true
	case "All report formats":
		opts.HTMLReport = true
		opts.JSONReport = true
		opts.CSVReport = true
		opts.TxtReport = true
	case "JSON report":
		opts.JSONReport = true
	default:
		opts.HTMLReport = true
	}
}

func defaultGuidedOutputPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "./reports"
	}
	return filepath.Join(home, "kubebuddy-report")
}

func selectTemplates() *promptui.SelectTemplates {
	return &promptui.SelectTemplates{
		Label:    "  {{ . }}",
		Active:   "\U0001F449 {{ . | cyan }}",
		Inactive: "   {{ . }}",
		Selected: "  \u2714 {{ . | cyan }}",
	}
}

func inputTemplates() *promptui.PromptTemplates {
	return &promptui.PromptTemplates{
		Prompt:  "  \U0001F4DD {{ . }}: ",
		Valid:   "  \U0001F4DD {{ . }}: ",
		Invalid: "  \U0001F4DD {{ . }}: ",
		Success: "  \u2714 {{ . }}: ",
	}
}

// promptTemplates kept for any external callers (backward compat).
func promptTemplates() *promptui.SelectTemplates { return selectTemplates() }
