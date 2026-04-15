package main

import (
	"fmt"
	"os"

	"github.com/KubeDeckio/KubeBuddy/internal/cli"
)

func main() {
	if err := cli.NewRootCommand().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
