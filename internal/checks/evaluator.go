package checks

import (
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"
)

type Evaluation struct {
	Failed bool
	Value  any
}

func EvaluateItem(check Check, item any) (Evaluation, error) {
	if check.Value == nil {
		return Evaluation{}, fmt.Errorf("check %s has no declarative value expression", check.ID)
	}

	value, err := resolveExpression(item, check.Value)
	if err != nil {
		return Evaluation{}, err
	}

	failed, err := evaluateOperator(check.Operator, value, check.Expected)
	if err != nil {
		return Evaluation{}, err
	}

	return Evaluation{Failed: failed, Value: value}, nil
}

func resolveExpression(item any, expr *Expression) (any, error) {
	if expr == nil {
		return nil, nil
	}
	if expr.Path != "" {
		return ResolvePath(item, expr.Path)
	}
	if expr.CountWhere != nil {
		value, err := ResolvePath(item, expr.CountWhere.Path)
		if err != nil {
			return nil, err
		}
		items := normalizeSlice(value)
		count := 0
		for _, candidate := range items {
			ok, err := evaluatePredicate(candidate, expr.CountWhere.Where)
			if err != nil {
				return nil, err
			}
			if ok {
				count++
			}
		}
		return count, nil
	}
	if len(expr.Coalesce) > 0 {
		for _, candidate := range expr.Coalesce {
			value, err := resolveExpression(item, candidate)
			if err != nil {
				return nil, err
			}
			if value != nil {
				return value, nil
			}
		}
		return nil, nil
	}
	if len(expr.Any) > 0 {
		for _, predicate := range expr.Any {
			ok, err := evaluatePredicate(item, predicate)
			if err != nil {
				return nil, err
			}
			if ok {
				return true, nil
			}
		}
		return false, nil
	}
	if len(expr.All) > 0 {
		for _, predicate := range expr.All {
			ok, err := evaluatePredicate(item, predicate)
			if err != nil {
				return nil, err
			}
			if !ok {
				return false, nil
			}
		}
		return true, nil
	}
	if expr.Value != nil {
		return expr.Value, nil
	}
	return nil, nil
}

func evaluatePredicate(item any, predicate Predicate) (bool, error) {
	if len(predicate.Any) > 0 {
		for _, child := range predicate.Any {
			ok, err := evaluatePredicate(item, child)
			if err != nil {
				return false, err
			}
			if ok {
				return true, nil
			}
		}
		return false, nil
	}
	if len(predicate.All) > 0 {
		for _, child := range predicate.All {
			ok, err := evaluatePredicate(item, child)
			if err != nil {
				return false, err
			}
			if !ok {
				return false, nil
			}
		}
		return true, nil
	}

	value, err := ResolvePath(item, predicate.Path)
	if err != nil {
		return false, err
	}
	failed, err := evaluateOperator(predicate.Operator, value, predicate.Expected)
	if err != nil {
		return false, err
	}
	return !failed, nil
}

func ResolvePath(item any, path string) (any, error) {
	current := item
	for _, part := range strings.Split(strings.TrimSpace(path), ".") {
		if part == "" {
			continue
		}

		flatten := strings.HasSuffix(part, "[]")
		field := strings.TrimSuffix(part, "[]")

		next, ok := lookupField(current, field)
		if !ok {
			return nil, nil
		}
		current = next

		if flatten {
			current = normalizeSlice(current)
		}
	}

	return current, nil
}

func evaluateOperator(op Operator, actual any, expected any) (bool, error) {
	expectedValues := normalizeExpectedValues(expected)

	switch op {
	case OperatorEquals:
		return !matchesAny(actual, expectedValues), nil
	case OperatorNotEquals:
		return matchesAny(actual, expectedValues), nil
	case OperatorContains:
		return !containsAny(actual, expectedValues), nil
	case OperatorNotContains:
		return containsAny(actual, expectedValues), nil
	case OperatorMatches:
		return !matchesPattern(actual, expectedValues), nil
	case OperatorNotMatches:
		return matchesPattern(actual, expectedValues), nil
	case OperatorGT:
		actualNum, ok := toFloat(actual)
		if !ok {
			return false, nil
		}
		expectedNum, ok := toFloat(firstExpected(expectedValues))
		if !ok {
			return false, nil
		}
		return actualNum <= expectedNum, nil
	case OperatorLT:
		actualNum, ok := toFloat(actual)
		if !ok {
			return false, nil
		}
		expectedNum, ok := toFloat(firstExpected(expectedValues))
		if !ok {
			return false, nil
		}
		return actualNum >= expectedNum, nil
	default:
		return false, fmt.Errorf("unsupported operator %q", op)
	}
}

func lookupField(item any, field string) (any, bool) {
	if item == nil {
		return nil, false
	}

	if items, ok := asSlice(item); ok {
		var collected []any
		for _, candidate := range items {
			value, found := lookupField(candidate, field)
			if !found {
				continue
			}
			if nested, ok := asSlice(value); ok {
				collected = append(collected, nested...)
				continue
			}
			collected = append(collected, value)
		}
		if len(collected) == 0 {
			return nil, false
		}
		return collected, true
	}

	v := reflect.ValueOf(item)
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return nil, false
		}
		v = v.Elem()
	}

	switch v.Kind() {
	case reflect.Map:
		for _, key := range v.MapKeys() {
			if strings.EqualFold(fmt.Sprint(key.Interface()), field) {
				value := v.MapIndex(key)
				if !value.IsValid() {
					return nil, false
				}
				return value.Interface(), true
			}
		}
	case reflect.Struct:
		t := v.Type()
		for i := 0; i < t.NumField(); i++ {
			sf := t.Field(i)
			if strings.EqualFold(sf.Name, field) {
				return v.Field(i).Interface(), true
			}
		}
	}

	return nil, false
}

func normalizeSlice(value any) []any {
	v := reflect.ValueOf(value)
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return nil
		}
		v = v.Elem()
	}

	if v.Kind() != reflect.Slice && v.Kind() != reflect.Array {
		if value == nil {
			return nil
		}
		return []any{value}
	}

	out := make([]any, 0, v.Len())
	for i := 0; i < v.Len(); i++ {
		out = append(out, v.Index(i).Interface())
	}
	return out
}

func normalizeExpectedValues(expected any) []any {
	switch value := expected.(type) {
	case string:
		parts := strings.Split(value, ",")
		out := make([]any, 0, len(parts))
		for _, part := range parts {
			out = append(out, normalizeExpectedToken(part))
		}
		return out
	case []any:
		return value
	default:
		return []any{expected}
	}
}

func normalizeExpectedToken(value string) any {
	trimmed := strings.TrimSpace(value)
	switch strings.ToLower(trimmed) {
	case "null", "":
		return nil
	case "true":
		return true
	case "false":
		return false
	}
	if i, err := strconv.ParseInt(trimmed, 10, 64); err == nil {
		return i
	}
	if f, err := strconv.ParseFloat(trimmed, 64); err == nil {
		return f
	}
	return trimmed
}

func matchesAny(actual any, expectedValues []any) bool {
	for _, actualValue := range actualValues(actual) {
		for _, expected := range expectedValues {
			if looselyEqual(actualValue, expected) {
				return true
			}
		}
	}
	return false
}

func containsAny(actual any, expectedValues []any) bool {
	for _, actualValue := range actualValues(actual) {
		actualText := strings.ToLower(strings.TrimSpace(fmt.Sprint(actualValue)))
		for _, expected := range expectedValues {
			expectedText := strings.ToLower(strings.TrimSpace(fmt.Sprint(expected)))
			if expected == nil && actualValue == nil {
				return true
			}
			if expectedText != "" && strings.Contains(actualText, expectedText) {
				return true
			}
		}
	}
	return false
}

func matchesPattern(actual any, expectedValues []any) bool {
	for _, actualValue := range actualValues(actual) {
		actualText := strings.TrimSpace(fmt.Sprint(actualValue))
		for _, expected := range expectedValues {
			pattern := strings.TrimSpace(fmt.Sprint(expected))
			if pattern == "" {
				continue
			}
			matched, err := regexp.MatchString(pattern, actualText)
			if err == nil && matched {
				return true
			}
		}
	}
	return false
}

func actualValues(value any) []any {
	if items, ok := asSlice(value); ok {
		out := make([]any, 0, len(items))
		for _, item := range items {
			out = append(out, actualValues(item)...)
		}
		return out
	}
	return []any{value}
}

func asSlice(value any) ([]any, bool) {
	v := reflect.ValueOf(value)
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return nil, false
		}
		v = v.Elem()
	}
	if v.Kind() != reflect.Slice && v.Kind() != reflect.Array {
		return nil, false
	}
	out := make([]any, 0, v.Len())
	for i := 0; i < v.Len(); i++ {
		out = append(out, v.Index(i).Interface())
	}
	return out, true
}

func looselyEqual(actual any, expected any) bool {
	if actual == nil || expected == nil {
		return actual == nil && expected == nil
	}

	if af, ok := toFloat(actual); ok {
		if ef, ok := toFloat(expected); ok {
			return af == ef
		}
	}

	if ab, ok := toBool(actual); ok {
		if eb, ok := toBool(expected); ok {
			return ab == eb
		}
	}

	return strings.EqualFold(strings.TrimSpace(fmt.Sprint(actual)), strings.TrimSpace(fmt.Sprint(expected)))
}

func toFloat(value any) (float64, bool) {
	switch v := value.(type) {
	case []any:
		return float64(len(v)), true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	case int32:
		return float64(v), true
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		return f, err == nil
	default:
		rv := reflect.ValueOf(value)
		for rv.Kind() == reflect.Pointer || rv.Kind() == reflect.Interface {
			if rv.IsNil() {
				return 0, false
			}
			rv = rv.Elem()
		}
		if rv.IsValid() && (rv.Kind() == reflect.Slice || rv.Kind() == reflect.Array) {
			return float64(rv.Len()), true
		}
		return 0, false
	}
}

func toBool(value any) (bool, bool) {
	switch v := value.(type) {
	case bool:
		return v, true
	case string:
		b, err := strconv.ParseBool(strings.TrimSpace(v))
		return b, err == nil
	default:
		return false, false
	}
}

func firstExpected(values []any) any {
	if len(values) == 0 {
		return nil
	}
	return values[0]
}
