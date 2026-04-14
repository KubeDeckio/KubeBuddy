package checks

import (
	"errors"
	"fmt"
	"strings"
)

type Severity string

const (
	SeverityLow     Severity = "Low"
	SeverityMedium  Severity = "Medium"
	SeverityHigh    Severity = "High"
	SeverityWarning Severity = "Warning"
	SeverityError   Severity = "Error"
)

type Operator string

const (
	OperatorEquals      Operator = "equals"
	OperatorNotEquals   Operator = "not_equals"
	OperatorContains    Operator = "contains"
	OperatorNotContains Operator = "not_contains"
	OperatorNotMatches  Operator = "not_matches"
	OperatorGT          Operator = "greater_than"
	OperatorGTE         Operator = "greater_than_or_equal"
	OperatorLT          Operator = "less_than"
	OperatorLTE         Operator = "less_than_or_equal"
	OperatorExists      Operator = "exists"
	OperatorMissing     Operator = "missing"
	OperatorMatches     Operator = "matches"
)

type RuleSet struct {
	Checks []Check `yaml:"checks"`
}

type Check struct {
	ID                         string         `yaml:"id"`
	Name                       string         `yaml:"name"`
	Category                   string         `yaml:"category"`
	Section                    string         `yaml:"section"`
	Severity                   Severity       `yaml:"severity"`
	Weight                     int            `yaml:"weight"`
	Description                string         `yaml:"description"`
	FailMessage                string         `yaml:"fail_message"`
	Recommendation             string         `yaml:"recommendation"`
	URL                        string         `yaml:"url"`
	Sources                    []string       `yaml:"sources"`
	ResourceKind               string         `yaml:"resource_kind"`
	AutomaticRelevance         string         `yaml:"automatic_relevance,omitempty"`
	AutomaticScope             string         `yaml:"automatic_scope,omitempty"`
	AutomaticReason            string         `yaml:"automatic_reason,omitempty"`
	AutomaticAdmissionBehavior string         `yaml:"automatic_admission_behavior,omitempty"`
	AutomaticMutationOutcome   string         `yaml:"automatic_mutation_outcome,omitempty"`
	When                       *Expression    `yaml:"when,omitempty"`
	Value                      *Expression    `yaml:"value,omitempty"`
	Operator                   Operator       `yaml:"operator,omitempty"`
	Expected                   any            `yaml:"expected,omitempty"`
	RecommendationHTML         string         `yaml:"recommendation_html,omitempty"`
	SpeechBubble               []string       `yaml:"speech_bubble,omitempty"`
	Prometheus                 *PrometheusRef `yaml:"prometheus,omitempty"`
	NativeHandler              string         `yaml:"native_handler,omitempty"`
}

type PrometheusRef struct {
	Query string          `yaml:"query"`
	Range PrometheusRange `yaml:"range"`
}

type PrometheusRange struct {
	Step     string `yaml:"step"`
	Duration string `yaml:"duration"`
}

// Expression is deliberately constrained so checks stay data-driven.
// More advanced behavior belongs in Go evaluator functions, not YAML-embedded code.
type Expression struct {
	Path       string          `yaml:"path,omitempty"`
	Value      any             `yaml:"value,omitempty"`
	Exists     string          `yaml:"exists,omitempty"`
	Len        *Expression     `yaml:"len,omitempty"`
	CountWhere *CountWhereExpr `yaml:"count_where,omitempty"`
	Any        []Predicate     `yaml:"any,omitempty"`
	All        []Predicate     `yaml:"all,omitempty"`
	Coalesce   []*Expression   `yaml:"coalesce,omitempty"`
}

type Predicate struct {
	Path     string      `yaml:"path,omitempty"`
	Operator Operator    `yaml:"operator,omitempty"`
	Expected any         `yaml:"expected,omitempty"`
	Any      []Predicate `yaml:"any,omitempty"`
	All      []Predicate `yaml:"all,omitempty"`
}

type CountWhereExpr struct {
	Path  string    `yaml:"path"`
	Where Predicate `yaml:"where"`
}

func (c Check) Validate() error {
	if strings.TrimSpace(c.ID) == "" {
		return errors.New("missing check id")
	}
	if strings.TrimSpace(c.Name) == "" {
		return fmt.Errorf("check %s: missing name", c.ID)
	}
	if strings.TrimSpace(c.Category) == "" {
		return fmt.Errorf("check %s: missing category", c.ID)
	}
	if strings.TrimSpace(string(c.Severity)) == "" {
		return fmt.Errorf("check %s: missing severity", c.ID)
	}
	if strings.TrimSpace(c.FailMessage) == "" {
		return fmt.Errorf("check %s: missing fail_message", c.ID)
	}
	if c.Value == nil && c.Prometheus == nil && strings.TrimSpace(c.NativeHandler) == "" {
		return fmt.Errorf("check %s: missing value, native_handler, or prometheus block", c.ID)
	}
	return nil
}

func (c Check) IsDeclarative() bool {
	if c.Prometheus != nil {
		return true
	}
	if strings.TrimSpace(c.NativeHandler) != "" {
		return true
	}
	return c.Value != nil
}
