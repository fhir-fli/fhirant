package fhirant

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

func initializeCollections(app *pocketbase.PocketBase) {
	app.OnAfterBootstrap().Add(func(e *core.BootstrapEvent) error {
		// Check if this is the first server load
		isFirstLoad, err := isFirstServerLoad(app)
		if err != nil {
			log.Printf("[ERROR] Failed to determine if it's the first server load: %v", err)
			return err
		} else if !isFirstLoad {
			log.Println("[INFO] Server initialization already complete. Skipping collection setup.")
			return nil
		}

		// Create the initial collections
		if err := createInitialCollections(app); err != nil {
			log.Printf("[ERROR] Failed to create initial collections: %v", err)
			return err
		}

		// Mark the server as initialized
		if err := markServerAsInitialized(app); err != nil {
			log.Printf("[ERROR] Failed to mark server as initialized: %v", err)
			return err
		}

		log.Println("[INFO] Initial collections setup complete.")
		return nil
	})
}

func isFirstServerLoad(app *pocketbase.PocketBase) (bool, error) {
	serverMetadata, err := app.Dao().FindCollectionByNameOrId("server_metadata")
	if err != nil || serverMetadata == nil {
		// Server metadata collection does not exist, meaning it's the first run
		return true, nil
	}

	// Check if `initialSetupComplete` is true
	records, err := app.Dao().FindRecordsByExpr("server_metadata", nil)
	if err != nil || len(records) == 0 {
		return true, nil // Assume it's the first load if no record exists
	}

	initialSetupField := records[0].GetBool("initialSetupComplete")
	return !initialSetupField, nil
}

func markServerAsInitialized(app *pocketbase.PocketBase) error {
	log.Println("[DEBUG] Marking server as initialized...")

	// Step 1: Ensure `server_metadata` collection exists
	serverMetadata, err := app.Dao().FindCollectionByNameOrId("server_metadata")
	if err != nil {
		log.Println("[DEBUG] 'server_metadata' collection does not exist. Creating it...")
		serverMetadata = &models.Collection{}
		form := forms.NewCollectionUpsert(app, serverMetadata)
		form.Name = "server_metadata"
		form.Type = models.CollectionTypeBase

		// Add `initialSetupComplete` field to schema
		form.Schema.AddField(&schema.SchemaField{
			Name:     "initialSetupComplete",
			Type:     schema.FieldTypeBool,
			Required: true,
			Options:  nil,
		})

		if err := form.Submit(); err != nil {
			return fmt.Errorf("failed to create 'server_metadata' collection: %v", err)
		}
		log.Println("[INFO] 'server_metadata' collection created successfully.")
	} else {
		log.Println("[INFO] 'server_metadata' collection already exists.")
	}

	// Step 2: Check if an initialization record already exists
	records, err := app.Dao().FindRecordsByExpr("server_metadata", nil)
	if err != nil {
		return fmt.Errorf("failed to query 'server_metadata' records: %v", err)
	}

	if len(records) == 0 {
		// Step 3: No record exists, create a new one
		log.Println("[DEBUG] Creating new initialization record for 'server_metadata'...")

		newRecord := models.NewRecord(serverMetadata)
		newRecord.Set("initialSetupComplete", true)

		if err := app.Dao().SaveRecord(newRecord); err != nil {
			return fmt.Errorf("failed to create 'server_metadata' initialization record: %v", err)
		}
		log.Println("[INFO] 'server_metadata' initialization record created successfully.")
	} else {
		// Step 4: Record already exists, update it if necessary
		existingRecord := records[0]
		if !existingRecord.GetBool("initialSetupComplete") {
			log.Println("[DEBUG] Updating the existing 'server_metadata' record to mark as initialized...")
			existingRecord.Set("initialSetupComplete", true)

			if err := app.Dao().SaveRecord(existingRecord); err != nil {
				return fmt.Errorf("failed to update 'server_metadata' initialization record: %v", err)
			}
			log.Println("[INFO] 'server_metadata' initialization record updated successfully.")
		} else {
			log.Println("[INFO] 'server_metadata' is already marked as initialized. No changes needed.")
		}
	}

	return nil
}

func createInitialCollections(app *pocketbase.PocketBase) error {
	if collections == nil {
		return fmt.Errorf("no collections to initialize")
	}

	for _, collection := range collections {
		collectionName, ok := collection["name"].(string)
		if !ok || collectionName == "" {
			log.Printf("[WARN] Invalid or missing collection name: %v", collection["name"])
			continue
		}

		collectionName = strings.ToLower(collectionName)

		existingCollection, err := app.Dao().FindCollectionByNameOrId(collectionName)
		if err == nil && existingCollection != nil {
			log.Printf("[INFO] Collection '%s' already exists. Skipping creation.", collectionName)
			continue
		}

		// Ensure schema exists and is of the correct type
		schemaFields, ok := collection["schema"].([]map[string]interface{})
		if !ok || len(schemaFields) == 0 {
			log.Printf("[WARN] No valid schema fields found for collection '%s'. Skipping creation.", collectionName)
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
				log.Printf("[WARN] Invalid field name in collection '%s'. Skipping field.", collectionName)
				continue
			}

			fieldType, ok := field["type"].(string)
			if !ok || fieldType == "" {
				log.Printf("[WARN] Invalid field type for field '%s' in collection '%s'. Skipping field.", fieldName, collectionName)
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
			log.Printf("[ERROR] Failed to create collection '%s': %v", collectionName, err)
			continue
		}

		log.Printf("[INFO] Collection '%s' created successfully", collectionName)
	}

	return nil
}
