package pocketfhir

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/fhir/go/fhirversion"
	"github.com/google/fhir/go/jsonformat"
	"github.com/google/fhir/go/jsonformat/fhirvalidate"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/models"
	"github.com/pocketbase/pocketbase/tools/types"
	"google.golang.org/protobuf/proto"
)

// Centralized function to update meta fields (lastUpdated and versionId)
func updateMeta(resourceJson map[string]interface{}) map[string]interface{} {
	meta, ok := resourceJson["meta"].(map[string]interface{})
	if !ok {
		meta = make(map[string]interface{})
	}

	// Set lastUpdated if missing
	if meta["lastUpdated"] == nil {
		now := time.Now().UTC().Format(time.RFC3339)
		meta["lastUpdated"] = now
	}

	// Ensure versionId matches lastUpdated
	lastUpdated := meta["lastUpdated"].(string)
	meta["versionId"] = strings.ReplaceAll(lastUpdated, ":", ".")

	resourceJson["meta"] = meta
	return resourceJson
}

// Handle resource creation in the FHIR database
func handleResourceCreation(app *pocketbase.PocketBase, e *core.RecordCreateEvent) error {
	log.Println("Starting resource creation...")

	resource := e.Record // Directly access the Record from the event
	collectionName := resource.Collection().Name
	log.Printf("Collection name: %s", collectionName)

	// Skip history collections
	if strings.HasSuffix(collectionName, "history") {
		log.Println("Collection is a history collection. Skipping creation.")
		return nil
	}

	if !isVersionedCollection(app, collectionName) {
		log.Println("Collection is not versioned. Skipping.")
		return nil
	}

	// Get resource data for validation and processing
	resourceField := resource.Get("resource")
	resourceData, err := getResourceData(resourceField)
	if err != nil {
		log.Printf("Failed to get resource data: %v", err)
		return fmt.Errorf("failed to get resource data: %w", err)
	}

	// Validate the FHIR resource
	if err := validateFHIRResource(resourceData); err != nil {
		log.Printf("FHIR validation failed: %v", err)
		return fmt.Errorf("validation error: %w", err)
	}

	// Check and update meta fields (lastUpdated and versionId)
	resourceData, err = updateMetaFields(resourceData)
	if err != nil {
		log.Printf("Failed to update meta fields: %v", err)
		return fmt.Errorf("failed to update meta fields: %w", err)
	}

	// Re-serialize the resource and store it
	resourceData, err = updateResourceJson(resourceData, e.Record.Id)
	if err != nil {
		log.Printf("Failed to update resource JSON: %v", err)
		return fmt.Errorf("failed to update resource JSON: %w", err)
	}

	log.Printf("Updated resource JSON for record %s: %s", resource.Id, resourceData)

	// Set the updated resource JSON back into the record
	resource.Set("resource", types.JsonRaw(resourceData))

	// Explicitly save the updated record in PocketBase
	if err := app.Dao().SaveRecord(resource); err != nil {
		log.Printf("Failed to save updated resource: %v", err)
		return fmt.Errorf("failed to save updated resource: %w", err)
	}

	log.Println("Resource creation completed successfully.")
	return nil
}

// Handle resource update in the FHIR database
func handleResourceUpdate(app *pocketbase.PocketBase, e *core.RecordUpdateEvent) error {
	log.Println("Starting resource update...")

	newResourceVersion := e.Record
	collectionName := newResourceVersion.Collection().Name
	log.Printf("Collection name: %s", collectionName)

	// Skip history collections
	if strings.HasSuffix(collectionName, "history") {
		log.Println("Collection is a history collection. Skipping update.")
		return nil
	}

	if !isVersionedCollection(app, collectionName) {
		log.Println("Collection is not versioned. Skipping.")
		return nil
	}

	// Fetch the current resource from the main table
	currentResource, err := app.Dao().FindRecordById(collectionName, newResourceVersion.Id)
	if err != nil {
		log.Printf("Failed to fetch existing resource: %v", err)
		return fmt.Errorf("failed to fetch existing resource: %w", err)
	}

	// Get resource data for validation and processing
	resourceField := newResourceVersion.Get("resource")
	resourceData, err := getResourceData(resourceField)
	if err != nil {
		log.Printf("Failed to get resource data: %v", err)
		return fmt.Errorf("failed to get resource data: %w", err)
	}

	// Validate the FHIR resource
	if err := validateFHIRResource(resourceData); err != nil {
		log.Printf("FHIR validation failed: %v", err)
		return fmt.Errorf("validation error: %w", err)
	}

	// Update meta fields (lastUpdated and versionId)
	resourceData, err = updateMetaFields(resourceData)
	if err != nil {
		log.Printf("Failed to update meta fields: %v", err)
		return fmt.Errorf("failed to update meta fields: %w", err)
	}

	// Check if the meta.lastUpdated exists
	meta := getMetaFromResource(resourceData)
	if meta.LastUpdated == "" {
		return fmt.Errorf("error: meta.lastUpdated is missing")
	}

	// Retrieve and assert current resource data as JsonRaw
	currentResourceField := currentResource.Get("resource")
	currentResourceData, ok := currentResourceField.(types.JsonRaw)
	if !ok {
		return fmt.Errorf("failed to assert current resource field as types.JsonRaw")
	}

	// Compare the lastUpdated fields between current and new resource
	currentMeta := getMetaFromResource([]byte(currentResourceData))
	if currentMeta.LastUpdated > meta.LastUpdated {
		log.Println("New resource is older. Moving new resource to history.")
		if err := moveResourceToHistory(app, collectionName, newResourceVersion); err != nil {
			return err
		}
	} else {
		log.Println("New resource is newer. Moving current resource to history.")
		if err := moveResourceToHistory(app, collectionName, currentResource); err != nil {
			return err
		}

		// Update the new resource with id and save it in the main table
		resourceData, err = updateResourceJson(resourceData, newResourceVersion.Id)
		if err != nil {
			log.Printf("Failed to update resource JSON: %v", err)
			return fmt.Errorf("failed to update resource JSON: %w", err)
		}

		newResourceVersion.Set("resource", types.JsonRaw(resourceData))

		// Save the updated resource in the main table
		if err := app.Dao().SaveRecord(newResourceVersion); err != nil {
			log.Printf("Failed to save updated resource: %v", err)
			return fmt.Errorf("failed to save updated resource: %w", err)
		}
	}

	log.Println("Resource update completed successfully.")
	return nil
}

// Function to update the resource JSON and ID, along with meta fields
func updateResourceJson(resourceData []byte, id string) ([]byte, error) {
	log.Println("Updating resource JSON...")

	var resourceJson map[string]interface{}
	if err := json.Unmarshal(resourceData, &resourceJson); err != nil {
		log.Printf("Failed to unmarshal resource JSON: %v", err)
		return nil, fmt.Errorf("failed to unmarshal resource JSON: %w", err)
	}

	resourceJson["id"] = id
	resourceJson = updateMeta(resourceJson) // Update meta fields

	updatedResourceBytes, err := json.Marshal(resourceJson)
	if err != nil {
		log.Printf("Failed to marshal updated resource JSON: %v", err)
		return nil, fmt.Errorf("failed to marshal updated resource JSON: %w", err)
	}

	return updatedResourceBytes, nil
}

// Determine if the collection is versioned by checking for the "lastUpdated" field
func isVersionedCollection(app *pocketbase.PocketBase, collectionName string) bool {
	collection, err := app.Dao().FindCollectionByNameOrId(collectionName)
	if err != nil {
		log.Printf("Failed to find collection: %v", err)
		return false
	}

	for _, field := range collection.Schema.Fields() {
		if field.Name == "lastUpdated" {
			return true
		}
	}
	return false
}

// Wrapper around updating meta fields for the resource
func updateMetaFields(resourceData []byte) ([]byte, error) {
	var resourceJson map[string]interface{}
	if err := json.Unmarshal(resourceData, &resourceJson); err != nil {
		return nil, fmt.Errorf("failed to unmarshal resource JSON: %w", err)
	}

	resourceJson = updateMeta(resourceJson) // Update meta fields

	return json.Marshal(resourceJson)
}

// Extract resource data
func getResourceData(resourceField any) (resourceData []byte, err error) {
	log.Println("Getting resource data...")

	switch v := resourceField.(type) {
	case types.JsonRaw:
		resourceData = []byte(v)
	default:
		log.Println("Resource field is not of expected type")
		return nil, fmt.Errorf("resource field is not of expected type")
	}

	log.Println("Resource data retrieved successfully.")
	return resourceData, nil
}

// Validate the FHIR resource
func validateFHIRResource(resourceData []byte) error {
	log.Println("Validating FHIR resource...")

	unmarshaller, err := jsonformat.NewUnmarshaller("UTC", fhirversion.R4) // Use "UTC" as the time zone and fhirversion.R4 for the FHIR version
	if err != nil {
		log.Printf("Failed to create unmarshaller: %v", err)
		return fmt.Errorf("failed to create unmarshaller: %w", err)
	}

	msg, err := unmarshaller.Unmarshal(resourceData)
	if err != nil {
		log.Printf("Failed to unmarshal FHIR resource: %v", err)
		return fmt.Errorf("failed to unmarshal FHIR resource: %w", err)
	}

	if err := fhirvalidate.Validate(proto.Message(msg)); err != nil {
		log.Printf("FHIR resource validation failed: %v", err)
		return fmt.Errorf("FHIR resource validation failed: %w", err)
	}

	log.Println("FHIR resource validation successful.")
	return nil
}

// Extract meta from resource JSON
func getMetaFromResource(resourceData []byte) *meta {
	var resourceJson map[string]interface{}
	if err := json.Unmarshal(resourceData, &resourceJson); err != nil {
		log.Printf("Failed to unmarshal resource data: %v", err)
		return &meta{}
	}

	metaData, ok := resourceJson["meta"].(map[string]interface{})
	if !ok {
		log.Println("Meta field not found in resource")
		return &meta{}
	}

	// Use safe type assertions to avoid panics
	lastUpdated, _ := metaData["lastUpdated"].(string)
	versionId, _ := metaData["versionId"].(string)

	return &meta{
		LastUpdated: lastUpdated,
		VersionId:   versionId,
	}
}

// Move resource to history table
func moveResourceToHistory(app *pocketbase.PocketBase, collectionName string, resource *models.Record) error {
	log.Printf("Moving resource with ID %s to history table...", resource.Id)

	historyCollectionName := collectionName + "history"

	historyCollection, err := app.Dao().FindCollectionByNameOrId(historyCollectionName)
	if err != nil {
		log.Printf("Failed to find history collection: %v", err)
		return fmt.Errorf("failed to find history collection: %w", err)
	}

	resourceField := resource.Get("resource")
	resourceData, ok := resourceField.(types.JsonRaw)
	if !ok {
		log.Println("Failed to assert resource field as types.JsonRaw")
		return fmt.Errorf("failed to assert resource field as types.JsonRaw")
	}

	historicalResource := models.NewRecord(historyCollection)
	historicalResource.Set("fhirId", resource.Id)
	historicalResource.Set("resourceType", resource.Get("resourceType"))

	meta := getMetaFromResource([]byte(resourceData))
	historicalResource.Set("lastUpdated", meta.LastUpdated) // Use lastUpdated as lastUpdated for history
	historicalResource.Set("resource", resourceData)

	log.Printf("Saving historical resource with lastUpdated %s to history table...", meta.LastUpdated)
	if err := app.Dao().SaveRecord(historicalResource); err != nil {
		log.Printf("Failed to save resource to history table: %v", err)
		return fmt.Errorf("failed to save resource to history table: %w", err)
	}

	log.Printf("Resource moved to history table successfully.")
	return nil
}

// meta struct to hold meta data fields
type meta struct {
	LastUpdated string
	VersionId   string
}
