package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/fhir-fli/fhirant/fhirant"
)

// Main entry point
func main() {
	// Parse the task flag
	task := flag.String("task", "default", "Task to perform (e.g., 'upload' or 'process')")
	flag.Parse()

	// Execute the task based on the flag
	switch *task {
	case "upload":
		runUploadScript()
	default:
		log.Fatalf("Unknown task: %s", *task)
	}
}

// runUploadScript handles the upload logic
func runUploadScript() {
	fmt.Println("Starting the upload script...")

	// Initialize FhirAnt with encryption key
	dbPath := "fhirant_test.db"
	encryptionKey := "01234567891123450123456789112345" // In production, use environment variables for security
	fhir, err := fhirant.NewFhirAnt(dbPath, encryptionKey)
	if err != nil {
		log.Fatalf("Failed to initialize FhirAnt: %v", err)
	}
	defer fhir.Close()

	// Define directories for JSON/NDJSON files
	fhirSpecPath := "../dart/assets/fhir_spec/"
	mimicIVPath := "../dart/assets/mimic_iv/"

	// Process the directories
	err = processNDJSONFiles(mimicIVPath, fhir)
	if err != nil {
		log.Fatalf("Failed to upload MIMIC-IV NDJSON files: %v", err)
	}
	err = processJSONFiles(fhirSpecPath, fhir)
	if err != nil {
		log.Fatalf("Failed to upload FHIR Spec JSON files: %v", err)
	}

	fmt.Println("Upload completed successfully.")
}

// processJSONFiles processes and uploads JSON files from a directory.
func processJSONFiles(dir string, fhir *fhirant.FhirAnt) error {
	return filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && filepath.Ext(path) == ".json" {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()

			var data map[string]interface{}
			if err := json.NewDecoder(file).Decode(&data); err != nil {
				return err
			}

			resourceType, ok := data["resourceType"].(string)
			if !ok {
				return fmt.Errorf("resourceType not found in %s", path)
			}

			resourceID, ok := data["id"].(string)
			if !ok {
				return fmt.Errorf("resource ID not found in %s", path)
			}

			if err := fhir.CreateResource(resourceType, resourceID, data); err != nil {
				return err
			}
		}
		return nil
	})
}

func processNDJSONFiles(dir string, fhir *fhirant.FhirAnt) error {
	fileCounter := 0 // Counter to keep track of processed files

	return filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Stop if we've already processed 5 files
		if fileCounter >= 5 {
			return filepath.SkipDir // This effectively stops the walk
		}

		// Process only .ndjson files
		if !info.IsDir() && filepath.Ext(path) == ".ndjson" {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()

			scanner := bufio.NewScanner(file)
			for scanner.Scan() {
				line := scanner.Text()

				var data map[string]interface{}
				if err := json.Unmarshal([]byte(line), &data); err != nil {
					return err
				}

				resourceType, ok := data["resourceType"].(string)
				if !ok {
					return fmt.Errorf("resourceType not found in %s", path)
				}

				resourceID, ok := data["id"].(string)
				if !ok {
					return fmt.Errorf("resource ID not found in %s", path)
				}

				if err := fhir.CreateResource(resourceType, resourceID, data); err != nil {
					return err
				}
			}

			if err := scanner.Err(); err != nil {
				return err
			}

			fileCounter++ // Increment the file counter
		}
		return nil
	})
}
