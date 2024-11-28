package main

import (
	"log"

	"github.com/fhir-fli/fhirant/fhirant"
)

func main() {
	// Initialize FhirAnt
	dbPath := "fhirant_test.db"
	encryptionKey := "01234567891123450123456789112345"
	fhir, err := fhirant.NewFhirAnt(dbPath, encryptionKey)
	if err != nil {
		log.Fatalf("Failed to initialize FhirAnt: %v", err)
	}
	defer fhir.Close()

	log.Println("FhirAnt initialized successfully.")
}
