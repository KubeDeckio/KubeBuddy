package checks

import (
	"fmt"
	"html"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

var (
	recommendationBacktickPattern = regexp.MustCompile("`([^`]+)`")
	recommendationQuotedPattern   = regexp.MustCompile(`'([^']+)'`)
)

type Recommendation struct {
	Text         string   `yaml:"text"`
	HTML         string   `yaml:"html"`
	SpeechBubble []string `yaml:"SpeechBubble"`
}

type rawRuleSet struct {
	Checks []rawCheck `yaml:"checks"`
}

type rawCheck struct {
	ID                         string         `yaml:"ID"`
	Name                       string         `yaml:"Name"`
	Category                   string         `yaml:"Category"`
	Section                    string         `yaml:"Section"`
	Severity                   string         `yaml:"Severity"`
	Weight                     int            `yaml:"Weight"`
	Description                string         `yaml:"Description"`
	FailMessage                string         `yaml:"FailMessage"`
	URL                        string         `yaml:"URL"`
	ResourceKind               string         `yaml:"ResourceKind"`
	AutomaticRelevance         string         `yaml:"AutomaticRelevance"`
	AutomaticScope             string         `yaml:"AutomaticScope"`
	AutomaticReason            string         `yaml:"AutomaticReason"`
	AutomaticAdmissionBehavior string         `yaml:"AutomaticAdmissionBehavior"`
	AutomaticMutationOutcome   string         `yaml:"AutomaticMutationOutcome"`
	Condition                  string         `yaml:"Condition"`
	Operator                   string         `yaml:"Operator"`
	Expected                   any            `yaml:"Expected"`
	NativeHandler              string         `yaml:"NativeHandler"`
	Script                     string         `yaml:"Script"`
	Prometheus                 *PrometheusRef `yaml:"Prometheus"`
	Recommendation             Recommendation `yaml:"Recommendation"`
	SpeechBubble               []string       `yaml:"SpeechBubble"`
}

func (r rawCheck) normalize() Check {
	check := Check{
		ID:                         strings.TrimSpace(r.ID),
		Name:                       strings.TrimSpace(r.Name),
		Category:                   strings.TrimSpace(r.Category),
		Section:                    strings.TrimSpace(r.Section),
		Severity:                   Severity(normalizeSeverity(r.Severity)),
		Weight:                     r.Weight,
		Description:                strings.TrimSpace(r.Description),
		FailMessage:                strings.TrimSpace(r.FailMessage),
		Recommendation:             strings.TrimSpace(r.Recommendation.Text),
		RecommendationHTML:         strings.TrimSpace(r.Recommendation.HTML),
		URL:                        strings.TrimSpace(r.URL),
		ResourceKind:               strings.TrimSpace(r.ResourceKind),
		AutomaticRelevance:         strings.TrimSpace(r.AutomaticRelevance),
		AutomaticScope:             strings.TrimSpace(r.AutomaticScope),
		AutomaticReason:            strings.TrimSpace(r.AutomaticReason),
		AutomaticAdmissionBehavior: strings.TrimSpace(r.AutomaticAdmissionBehavior),
		AutomaticMutationOutcome:   strings.TrimSpace(r.AutomaticMutationOutcome),
		Operator:                   normalizeOperator(r.Operator),
		Expected:                   r.Expected,
		NativeHandler:              strings.TrimSpace(r.NativeHandler),
		SpeechBubble:               compactStrings(firstNonEmptySlice(r.SpeechBubble, r.Recommendation.SpeechBubble)),
		Prometheus:                 r.Prometheus,
		Script:                     strings.TrimSpace(r.Script),
	}

	if condition := strings.TrimSpace(r.Condition); condition != "" {
		check.Value = &Expression{Path: condition}
	}
	if check.FailMessage == "" {
		check.FailMessage = firstNonEmptyString(check.Description, check.Name)
	}
	if check.IsScripted() {
		check.LegacyScripted = true
	}
	hydrateRecommendationVariants(&check)

	return check
}

func LoadFile(path string) (RuleSet, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return RuleSet{}, err
	}

	var direct RuleSet
	if err := yaml.Unmarshal(data, &direct); err == nil && looksLikeModernRuleSet(direct) {
		for i := range direct.Checks {
			direct.Checks[i].ID = strings.TrimSpace(direct.Checks[i].ID)
			hydrateRecommendationVariants(&direct.Checks[i])
			if err := direct.Checks[i].Validate(); err != nil {
				return RuleSet{}, fmt.Errorf("%s: %w", path, err)
			}
		}
		return direct, nil
	}

	var raw rawRuleSet
	if err := yaml.Unmarshal(data, &raw); err != nil {
		return RuleSet{}, fmt.Errorf("parse %s: %w", path, err)
	}

	out := RuleSet{Checks: make([]Check, 0, len(raw.Checks))}
	for _, item := range raw.Checks {
		check := item.normalize()
		if err := check.Validate(); err != nil {
			return RuleSet{}, fmt.Errorf("%s: %w", path, err)
		}
		out.Checks = append(out.Checks, check)
	}

	return out, nil
}

func LoadDir(dir string) (RuleSet, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return RuleSet{}, err
	}

	var files []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		switch strings.ToLower(filepath.Ext(entry.Name())) {
		case ".yaml", ".yml":
			files = append(files, filepath.Join(dir, entry.Name()))
		}
	}
	sort.Strings(files)

	out := RuleSet{}
	for _, path := range files {
		fileChecks, err := LoadFile(path)
		if err != nil {
			return RuleSet{}, err
		}
		out.Checks = append(out.Checks, fileChecks.Checks...)
	}

	return out, nil
}

type Inventory struct {
	Total          int
	Declarative    int
	Prometheus     int
	LegacyScripted int
	ByCategory     map[string]int
	BySection      map[string]int
}

func Summarize(ruleSet RuleSet) Inventory {
	out := Inventory{
		Total:      len(ruleSet.Checks),
		ByCategory: map[string]int{},
		BySection:  map[string]int{},
	}

	for _, check := range ruleSet.Checks {
		switch {
		case check.Prometheus != nil:
			out.Prometheus++
		case check.IsDeclarative():
			out.Declarative++
		case check.IsScripted():
			out.LegacyScripted++
		}

		if check.Category != "" {
			out.ByCategory[check.Category]++
		}
		if check.Section != "" {
			out.BySection[check.Section]++
		}
	}

	return out
}

func compactStrings(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		out = append(out, trimmed)
	}
	return out
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func firstNonEmptySlice(values ...[]string) []string {
	for _, value := range values {
		if len(value) > 0 {
			return value
		}
	}
	return nil
}

func hydrateRecommendationVariants(check *Check) {
	if check == nil {
		return
	}
	check.Recommendation = strings.TrimSpace(check.Recommendation)
	check.RecommendationHTML = strings.TrimSpace(check.RecommendationHTML)
	check.SpeechBubble = compactStrings(check.SpeechBubble)
	if check.RecommendationHTML == "" && check.Recommendation != "" {
		check.RecommendationHTML = synthesizeRecommendationHTML(check.Recommendation)
	}
	if len(check.SpeechBubble) == 0 && check.Recommendation != "" {
		check.SpeechBubble = synthesizeSpeechBubble(check.Recommendation)
	}
}

func synthesizeRecommendationHTML(text string) string {
	clauses := splitRecommendationClauses(text)
	if len(clauses) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString(`<div class="recommendation-content"><ul>`)
	for _, clause := range clauses {
		b.WriteString(`<li>` + inlineRecommendationHTML(clause) + `</li>`)
	}
	b.WriteString(`</ul></div>`)
	return b.String()
}

func synthesizeSpeechBubble(text string) []string {
	clauses := splitRecommendationClauses(text)
	if len(clauses) == 0 {
		return nil
	}
	first := strings.TrimSpace(clauses[0])
	if len(first) > 140 {
		first = strings.TrimSpace(first[:137]) + "..."
	}
	return []string{first}
}

func splitRecommendationClauses(text string) []string {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	raw := strings.FieldsFunc(text, func(r rune) bool {
		return r == '\n' || r == ';'
	})
	var clauses []string
	for _, item := range raw {
		for _, part := range strings.Split(item, ". ") {
			part = strings.TrimSpace(part)
			if part == "" {
				continue
			}
			part = strings.TrimSpace(strings.TrimSuffix(part, "."))
			if part == "" {
				continue
			}
			clauses = append(clauses, part)
		}
	}
	return clauses
}

func inlineRecommendationHTML(text string) string {
	text = html.EscapeString(strings.TrimSpace(text))
	text = recommendationBacktickPattern.ReplaceAllString(text, `<code>$1</code>`)
	text = recommendationQuotedPattern.ReplaceAllStringFunc(text, func(match string) string {
		if len(match) < 3 {
			return match
		}
		content := match[1 : len(match)-1]
		if !looksLikeRecommendationCode(content) {
			return match
		}
		return `<code>` + html.EscapeString(content) + `</code>`
	})
	return text
}

func looksLikeRecommendationCode(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" {
		return false
	}
	return strings.Contains(value, "--") ||
		strings.Contains(value, "<") ||
		strings.Contains(value, ">") ||
		strings.Contains(value, "_") ||
		strings.HasPrefix(value, "az ") ||
		strings.HasPrefix(value, "kubectl ") ||
		strings.HasPrefix(value, "helm ") ||
		strings.HasPrefix(value, "terraform ") ||
		strings.HasPrefix(value, "/")
}

func normalizeSeverity(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "critical", "high":
		return string(SeverityHigh)
	case "warning":
		return string(SeverityWarning)
	case "error":
		return string(SeverityError)
	case "medium":
		return string(SeverityMedium)
	case "low":
		return string(SeverityLow)
	default:
		return strings.TrimSpace(value)
	}
}

func normalizeOperator(value string) Operator {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "equals":
		return OperatorEquals
	case "not_equals":
		return OperatorNotEquals
	case "contains":
		return OperatorContains
	case "not_contains":
		return OperatorNotContains
	case "not_matches":
		return OperatorNotMatches
	case "greater_than":
		return OperatorGT
	case "greater_than_or_equal":
		return OperatorGTE
	case "less_than":
		return OperatorLT
	case "less_than_or_equal":
		return OperatorLTE
	case "exists":
		return OperatorExists
	case "missing":
		return OperatorMissing
	case "matches":
		return OperatorMatches
	default:
		return Operator(strings.TrimSpace(value))
	}
}

func looksLikeModernRuleSet(ruleSet RuleSet) bool {
	if len(ruleSet.Checks) == 0 {
		return false
	}
	for _, check := range ruleSet.Checks {
		if strings.TrimSpace(check.ID) == "" {
			return false
		}
	}
	return true
}
