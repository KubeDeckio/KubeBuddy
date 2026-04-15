package runner

import (
	"fmt"
	"sync"

	"github.com/KubeDeckio/KubeBuddy/internal/ai"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

func enrichWithAI(result *scan.Result) int {
	client := ai.NewFromEnv()
	if client == nil {
		return 0
	}

	sem := make(chan struct{}, 3)
	var wg sync.WaitGroup
	var mu sync.Mutex
	enriched := 0
	for i := range result.Checks {
		check := &result.Checks[i]
		if check.Total == 0 {
			continue
		}
		wg.Add(1)
		go func(check *scan.CheckResult) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			rec, err := client.Recommend(check.ID, check.Name, check.Description, check.Items)
			if err != nil {
				return
			}
			check.Recommendation = rec.Text
			check.RecommendationHTML = rec.HTML
			check.RecommendationSource = "AI"
			mu.Lock()
			enriched++
			mu.Unlock()
		}(check)
	}
	wg.Wait()
	if enriched > 0 {
		fmt.Printf("[AI] enriched %d failing checks\n", enriched)
	}
	return enriched
}
