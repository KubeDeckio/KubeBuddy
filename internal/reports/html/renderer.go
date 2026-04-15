package html

import (
	"bytes"
	"html/template"
	"time"

	reportassets "github.com/KubeDeckio/KubeBuddy/internal/reports/assets"
	"github.com/KubeDeckio/KubeBuddy/internal/model"
)

type Renderer struct{}

type viewModel struct {
	Title       string
	GeneratedAt string
	Styles      template.CSS
	BodyHTML    template.HTML
	Scripts     template.JS
}

var pageTemplate = template.Must(template.New("report").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ .Title }}</title>
  <link rel="icon" href="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/assets/images/favicon.ico" type="image/x-icon">
  <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js"></script>
  <style>{{ .Styles }}</style>
</head>
<body>
  {{ .BodyHTML }}
  <script>{{ .Scripts }}</script>
</body>
</html>
`))

func (Renderer) Render(doc model.ReportDocument) (string, error) {
	if doc.GeneratedAt.IsZero() {
		doc.GeneratedAt = time.Now().UTC()
	}

	vm := viewModel{
		Title:       doc.Title,
		GeneratedAt: doc.GeneratedAt.Format(time.RFC3339),
		Styles:      template.CSS(reportassets.ReportStyles),
		BodyHTML:    template.HTML(doc.BodyHTML),
		Scripts:     template.JS(reportassets.ReportScripts),
	}

	var out bytes.Buffer
	if err := pageTemplate.Execute(&out, vm); err != nil {
		return "", err
	}

	return out.String(), nil
}
