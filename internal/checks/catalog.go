package checks

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func LoadCatalog(primaryDir string) (RuleSet, error) {
	dirs := []string{primaryDir}
	if isDefaultKubernetesCatalog(primaryDir) {
		overrideDir := resolveSiblingDir(primaryDir, "checks/kubernetes")
		if dirExists(overrideDir) {
			dirs = []string{overrideDir, primaryDir}
		}
	}
	return LoadMergedDirs(dirs...)
}

func LoadMergedDirs(dirs ...string) (RuleSet, error) {
	seen := map[string]struct{}{}
	out := RuleSet{}

	for _, dir := range dirs {
		trimmed := strings.TrimSpace(dir)
		if trimmed == "" || !dirExists(trimmed) {
			continue
		}

		ruleSet, err := LoadDir(trimmed)
		if err != nil {
			return RuleSet{}, err
		}

		for _, check := range ruleSet.Checks {
			id := strings.TrimSpace(check.ID)
			if id == "" {
				continue
			}
			if _, ok := seen[id]; ok {
				continue
			}
			seen[id] = struct{}{}
			out.Checks = append(out.Checks, check)
		}
	}

	sort.Slice(out.Checks, func(i, j int) bool {
		return out.Checks[i].ID < out.Checks[j].ID
	})
	return out, nil
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}

func isDefaultKubernetesCatalog(path string) bool {
	normalized := filepath.ToSlash(filepath.Clean(strings.TrimSpace(path)))
	return normalized == "Private/yamlChecks" || strings.HasSuffix(normalized, "/Private/yamlChecks")
}

func resolveSiblingDir(primaryDir string, sibling string) string {
	normalizedPrimary := filepath.Clean(strings.TrimSpace(primaryDir))
	if normalizedPrimary == "Private/yamlChecks" {
		return sibling
	}

	root := filepath.Dir(filepath.Dir(normalizedPrimary))
	if root == "." || root == string(filepath.Separator) {
		return sibling
	}
	return filepath.Join(root, sibling)
}
