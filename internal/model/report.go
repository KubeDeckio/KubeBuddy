package model

import "time"

type ReportDocument struct {
	Title       string
	GeneratedAt time.Time
	BodyHTML    string
}
