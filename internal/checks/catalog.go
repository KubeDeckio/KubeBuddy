package checks

import (
	"os"
	"sort"
	"strings"
)

func LoadCatalog(primaryDir string) (RuleSet, error) {
	return LoadMergedDirs(primaryDir)
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
