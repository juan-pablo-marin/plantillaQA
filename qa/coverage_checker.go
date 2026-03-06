package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	coverageFile := flag.String("file", "fuc-sena/coverage.out", "Path to the coverage profile file")
	threshold := flag.Float64("threshold", 70.0, "Minimum coverage percentage required")
	flag.Parse()

	file, err := os.Open(*coverageFile)
	if err != nil {
		fmt.Printf("Error opening coverage file: %v\n", err)
		os.Exit(1)
	}
	defer file.Close()

	var totalStatements, coveredStatements int64
	scanner := bufio.NewScanner(file)

	// Skip the first line: "mode: set" or "mode: atomic"
	if scanner.Scan() {
		// First line skipped
	}

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Fields(line)
		if len(parts) < 3 {
			continue
		}

		// Line format: name.go:line.column,line.column numStmt count
		// numStmt is parts[len(parts)-2]
		// count is parts[len(parts)-1]
		numStmt, err := strconv.ParseInt(parts[len(parts)-2], 10, 64)
		if err != nil {
			continue
		}
		count, err := strconv.ParseInt(parts[len(parts)-1], 10, 64)
		if err != nil {
			continue
		}

		totalStatements += numStmt
		if count > 0 {
			coveredStatements += numStmt
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("Error reading coverage file: %v\n", err)
		os.Exit(1)
	}

	if totalStatements == 0 {
		fmt.Println("No statements found in coverage file.")
		os.Exit(1)
	}

	percentage := (float64(coveredStatements) / float64(totalStatements)) * 100
	fmt.Printf("Total Statements:   %d\n", totalStatements)
	fmt.Printf("Covered Statements: %d\n", coveredStatements)
	fmt.Printf("Current Coverage:   %.2f%%\n", percentage)
	fmt.Printf("Required Threshold: %.2f%%\n", *threshold)

	if percentage < *threshold {
		fmt.Printf("❌ FAILED: Coverage is below threshold!\n")
		os.Exit(1)
	}

	fmt.Printf("✅ SUCCESS: Coverage meets threshold.\n")
}
