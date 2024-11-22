package pocketfhir

import (
	"fmt"
	"log"
	"strings"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/forms"
	"github.com/pocketbase/pocketbase/models"
	"github.com/pocketbase/pocketbase/models/schema"
	"github.com/pocketbase/pocketbase/tools/types"
)

func initializeCollections(app *pocketbase.PocketBase) error {
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		// Step 1: Create necessary collections
		if err := createInitialCollections(app); err != nil {
			log.Printf("Failed to create initial collections: %v", err)
			return err
		}

		return nil
	})
	return nil
}

func createInitialCollections(app *pocketbase.PocketBase) error {
	if collections == nil {
		return fmt.Errorf("no collections to initialize")
	}

	for _, collection := range collections {
		collectionName, ok := collection["name"].(string)
		if !ok || collectionName == "" {
			log.Printf("Invalid or missing collection name: %v", collection["name"])
			continue
		}

		collectionName = strings.ToLower(collectionName)

		existingCollection, err := app.Dao().FindCollectionByNameOrId(collectionName)
		if err == nil && existingCollection != nil {
			log.Printf("Collection '%s' already exists. Skipping creation.", collectionName)
			continue
		}

		// Ensure schema exists and is of the correct type
		schemaFields, ok := collection["schema"].([]map[string]interface{})
		if !ok || len(schemaFields) == 0 {
			log.Printf("No valid schema fields found for collection '%s'. Skipping creation.", collectionName)
			continue
		}

		coll := &models.Collection{}
		form := forms.NewCollectionUpsert(app, coll)
		form.Name = collectionName
		form.Type = models.CollectionTypeBase
		form.ListRule = types.Pointer("@request.auth.id != ''")
		form.ViewRule = types.Pointer("@request.auth.id != ''")
		form.CreateRule = types.Pointer("@request.auth.id != ''")
		form.UpdateRule = types.Pointer("@request.auth.id != ''")
		form.DeleteRule = nil

		// Add fields to the schema based on the collection's schema definition
		for _, field := range schemaFields {
			fieldName, ok := field["name"].(string)
			if !ok || fieldName == "" {
				log.Printf("Invalid field name in collection '%s'. Skipping field.", collectionName)
				continue
			}

			fieldType, ok := field["type"].(string)
			if !ok || fieldType == "" {
				log.Printf("Invalid field type for field '%s' in collection '%s'. Skipping field.", fieldName, collectionName)
				continue
			}

			required, _ := field["required"].(bool)
			options, _ := field["options"].(map[string]interface{})

			form.Schema.AddField(&schema.SchemaField{
				Name:     fieldName,
				Type:     fieldType,
				Required: required,
				Options:  options,
			})
		}

		// Submit the form to create the collection
		if err := form.Submit(); err != nil {
			log.Printf("Failed to create collection '%s': %v", collectionName, err)
			continue
		}

		log.Printf("Collection '%s' created successfully", collectionName)
	}

	return nil
}
