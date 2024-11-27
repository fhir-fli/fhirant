package main

import (
	"log"

	"github.com/fhir-fli/fhirant"
)

func main() {
	// Initialize FhirAnt
	dbPath := "fhirant_test.db"
	fhir, err := fhirant.NewFhirAnt(dbPath)
	if err != nil {
		log.Fatalf("Failed to initialize FhirAnt: %v", err)
	}
	defer fhir.Close()

	log.Println("FhirAnt initialized successfully.")
}
