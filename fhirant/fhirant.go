package fhirant

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/fhir-fli/fhirant/db"
	"github.com/fhir-fli/fhirant/utils"
)

// FhirAnt struct encapsulates database connection and package methods.
type FhirAnt struct {
	DBPath string
	DB     *db.SQLiteDB
}

// NewFhirAnt initializes the FhirAnt package with SQLCipher encryption.
func NewFhirAnt(dbPath, encryptionKey string) (*FhirAnt, error) {
	utils.InitLogger()

	conn, err := db.ConnectSQLite(dbPath, encryptionKey)
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

// CreateResource creates a new FHIR resource in the corresponding table.
func (f *FhirAnt) CreateResource(resourceType, resourceID string, resourceData map[string]interface{}) error {
	resourceJSON, err := json.Marshal(resourceData)
	if err != nil {
		return fmt.Errorf("failed to marshal resource data: %w", err)
	}

	lastUpdated := time.Now().UTC()
	query := fmt.Sprintf(`
		INSERT INTO %s (id, lastUpdated, resourceJson) VALUES (?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET lastUpdated = excluded.lastUpdated, resourceJson = excluded.resourceJson;
	`, resourceType)

	_, err = f.DB.GetConnection().Exec(query, resourceID, lastUpdated, string(resourceJSON))
	if err != nil {
		return fmt.Errorf("failed to insert resource into %s: %w", resourceType, err)
	}
	return nil
}

// GetResource retrieves a FHIR resource by ID.
func (f *FhirAnt) GetResource(resourceType, resourceID string) (map[string]interface{}, error) {
	query := fmt.Sprintf(`SELECT resourceJson FROM %s WHERE id = ?;`, resourceType)
	var resourceJSON string

	err := f.DB.GetConnection().QueryRow(query, resourceID).Scan(&resourceJSON)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("resource not found")
		}
		return nil, fmt.Errorf("failed to get resource from %s: %w", resourceType, err)
	}

	var resourceData map[string]interface{}
	if err := json.Unmarshal([]byte(resourceJSON), &resourceData); err != nil {
		return nil, fmt.Errorf("failed to unmarshal resource data: %w", err)
	}

	return resourceData, nil
}

// UpdateResource updates an existing FHIR resource.
func (f *FhirAnt) UpdateResource(resourceType, resourceID string, resourceData map[string]interface{}) error {
	resourceJSON, err := json.Marshal(resourceData)
	if err != nil {
		return fmt.Errorf("failed to marshal resource data: %w", err)
	}

	lastUpdated := time.Now().UTC()
	query := fmt.Sprintf(`UPDATE %s SET lastUpdated = ?, resourceJson = ? WHERE id = ?;`, resourceType)
	result, err := f.DB.GetConnection().Exec(query, lastUpdated, string(resourceJSON), resourceID)
	if err != nil {
		return fmt.Errorf("failed to update resource in %s: %w", resourceType, err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("resource not found")
	}
	return nil
}

// DeleteResource removes a FHIR resource by ID.
func (f *FhirAnt) DeleteResource(resourceType, resourceID string) error {
	query := fmt.Sprintf(`DELETE FROM %s WHERE id = ?;`, resourceType)
	result, err := f.DB.GetConnection().Exec(query, resourceID)
	if err != nil {
		return fmt.Errorf("failed to delete resource from %s: %w", resourceType, err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to check rows affected: %w", err)
	}

	if rowsAffected == 0 {
		return fmt.Errorf("resource not found")
	}
	return nil
}

// QueryResources retrieves resources based on filters.
func (f *FhirAnt) QueryResources(resourceType string, filters map[string]interface{}) ([]map[string]interface{}, error) {
	query := fmt.Sprintf(`SELECT resourceJson FROM %s WHERE 1=1`, resourceType)
	args := []interface{}{}

	for key, value := range filters {
		query += fmt.Sprintf(" AND JSON_EXTRACT(resourceJson, '$.%s') = ?", key)
		args = append(args, value)
	}

	rows, err := f.DB.GetConnection().Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query resources from %s: %w", resourceType, err)
	}
	defer rows.Close()

	var results []map[string]interface{}
	for rows.Next() {
		var resourceJSON string
		if err := rows.Scan(&resourceJSON); err != nil {
			return nil, err
		}
		var resource map[string]interface{}
		if err := json.Unmarshal([]byte(resourceJSON), &resource); err != nil {
			return nil, err
		}
		results = append(results, resource)
	}

	return results, nil
}
