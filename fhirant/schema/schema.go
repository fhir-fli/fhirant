package schema

import (
	"encoding/json"
	"fmt"
	"os"
)

type FHIRSchema map[string]interface{}

// LoadSchema loads a FHIR schema from a JSON file
func LoadSchema(filePath string) (FHIRSchema, error) {
	file, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read schema file: %w", err)
	}

	var schema FHIRSchema
	if err := json.Unmarshal(file, &schema); err != nil {
		return nil, fmt.Errorf("failed to parse schema JSON: %w", err)
	}

	return schema, nil
}

// ValidateResource checks if a resource conforms to the schema
func (s FHIRSchema) ValidateResource(resourceType string, resourceData map[string]interface{}) error {
	// Example: Validate that required fields exist
	if _, ok := s[resourceType]; !ok {
		return fmt.Errorf("resource type '%s' not found in schema", resourceType)
	}
	// Add validation logic here...
	return nil
}
