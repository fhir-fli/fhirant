package fhirant

import (
	"fhirant/db"
	"fhirant/utils"
	"log"
)

// FhirAnt struct encapsulates database connection and package methods.
type FhirAnt struct {
	DBPath string
	DB     *db.DuckDB
}

// NewFhirAnt initializes the FhirAnt package.
func NewFhirAnt(dbPath string) (*FhirAnt, error) {
	utils.InitLogger()

	conn, err := db.ConnectDuckDB(dbPath)
	if err != nil {
		return nil, err
	}

	// Ensure the schema exists
	if err := db.InitSchema(conn); err != nil {
		return nil, err
	}

	return &FhirAnt{
		DBPath: dbPath,
		DB:     conn,
	}, nil
}

// Close cleans up resources.
func (f *FhirAnt) Close() {
	if err := f.DB.Close(); err != nil {
		log.Printf("Error closing database: %v", err)
	}
	log.Println("FhirAnt closed successfully.")
}
