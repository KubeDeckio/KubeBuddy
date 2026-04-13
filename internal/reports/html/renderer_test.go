package html

import (
	"strings"
	"testing"

	reportassets "github.com/KubeDeckio/KubeBuddy/internal/reports/assets"
	"github.com/KubeDeckio/KubeBuddy/internal/model"
)

func TestRendererIncludesCurrentAssets(t *testing.T) {
	t.Helper()

	out, err := (Renderer{}).Render(model.ReportDocument{
		Title:    "KubeBuddy Report",
		BodyHTML: `<main id="report-root"><section id="summary">summary</section></main>`,
	})
	if err != nil {
		t.Fatalf("render report: %v", err)
	}

	if !strings.Contains(out, reportassets.ReportStyles) {
		t.Fatalf("rendered report does not include current report styles")
	}

	if !strings.Contains(out, reportassets.ReportScripts) {
		t.Fatalf("rendered report does not include current report scripts")
	}

	if !strings.Contains(out, `https://cdn.jsdelivr.net/npm/chart.js`) {
		t.Fatalf("rendered report does not include chart.js dependency")
	}

	if !strings.Contains(out, `https://fonts.googleapis.com/icon?family=Material+Icons`) {
		t.Fatalf("rendered report does not include material icons dependency")
	}

	if !strings.Contains(out, `id="report-root"`) {
		t.Fatalf("rendered report does not include caller-provided body html")
	}
}
