package checks

import (
	"os"
	"sort"
	"strings"

	bundled "github.com/KubeDeckio/KubeBuddy/checks"
)

type CatalogSource string

const (
	CatalogSourceFilesystem CatalogSource = "filesystem"
	CatalogSourceEmbedded   CatalogSource = "embedded"
	CatalogSourceEmpty      CatalogSource = "empty"
)

type Catalog struct {
	RuleSet RuleSet
	Source  CatalogSource
}

func LoadCatalog(primaryDir string) (RuleSet, error) {
	catalog, err := LoadCatalogWithSource(primaryDir)
	return catalog.RuleSet, err
}

func LoadCatalogWithSource(primaryDir string) (Catalog, error) {
	ruleSet, err := LoadMergedDirs(primaryDir)
	if err != nil {
		return Catalog{}, err
	}
	if len(ruleSet.Checks) > 0 {
		return Catalog{RuleSet: ruleSet, Source: CatalogSourceFilesystem}, nil
	}
	ruleSet, err = loadBundledCatalog(primaryDir)
	if err != nil {
		return Catalog{}, err
	}
	source := CatalogSourceEmbedded
	if len(ruleSet.Checks) == 0 {
		source = CatalogSourceEmpty
	}
	return Catalog{RuleSet: ruleSet, Source: source}, nil
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

func loadBundledCatalog(primaryDir string) (RuleSet, error) {
	switch normalizeCatalogDir(primaryDir) {
	case "aks", "gke", "kubernetes":
		return LoadFSDir(bundled.FS, normalizeCatalogDir(primaryDir))
	default:
		return RuleSet{}, nil
	}
}

func normalizeCatalogDir(dir string) string {
	trimmed := strings.Trim(strings.ReplaceAll(strings.TrimSpace(dir), "\\", "/"), "/")
	trimmed = strings.TrimPrefix(trimmed, "./")
	trimmed = strings.TrimPrefix(trimmed, "checks/")
	return trimmed
}
