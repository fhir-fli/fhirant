package db

import (
	"database/sql"
	"fmt"

	_ "github.com/marcboeker/go-duckdb" // Import the DuckDB driver
)

// DuckDB struct wraps a DuckDB connection.
type DuckDB struct {
	conn *sql.DB
}

// ConnectDuckDB establishes a connection to the DuckDB database.
func ConnectDuckDB(dbPath string) (*DuckDB, error) {
	conn, err := sql.Open("duckdb", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to DuckDB: %w", err)
	}
	return &DuckDB{conn: conn}, nil
}

// Close terminates the DuckDB connection.
func (db *DuckDB) Close() error {
	return db.conn.Close()
}

// InitSchema ensures the FHIR schema exists in the database.
func InitSchema(db *DuckDB) error {
	schema := `
	CREATE TABLE IF NOT EXISTS resources (
		resource_id TEXT PRIMARY KEY,
		resource_type TEXT NOT NULL,
		resource_data JSONB NOT NULL
	);
	`
	if _, err := db.conn.Exec(schema); err != nil {
		return fmt.Errorf("failed to initialize schema: %w", err)
	}
	return nil
}
