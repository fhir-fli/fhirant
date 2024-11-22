package fhirant

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/labstack/echo/v5"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/models"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Fetch FHIR resource by ID
func getFHIRResource(c echo.Context, app *pocketbase.PocketBase) error {
	resourceType := c.PathParam("resourceType")
	id := c.PathParam("id")

	collection, err := app.Dao().FindCollectionByNameOrId(resourceType)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "Collection not found"})
	}

	resource, err := app.Dao().FindRecordById(collection.Id, id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "Resource not found"})
	}

	return c.JSON(http.StatusOK, map[string]interface{}{
		"id":       resource.Id,
		"resource": resource.Get("resource"),
	})
}

// Create or update a FHIR resource
func createOrUpdateFHIRResource(c echo.Context, app *pocketbase.PocketBase) error {
	resourceType := c.PathParam("resourceType")

	var resourceData map[string]interface{}
	if err := c.Bind(&resourceData); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid JSON data"})
	}

	collection, err := app.Dao().FindCollectionByNameOrId(resourceType)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "Collection not found"})
	}

	id, ok := resourceData["id"].(string)
	var record *models.Record

	if ok && id != "" {
		record, err = app.Dao().FindRecordById(collection.Id, id)
		if err != nil {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "Resource not found"})
		}
	} else {
		record = models.NewRecord(collection)
	}

	resourceJSON, err := json.Marshal(resourceData)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to process resource data"})
	}
	record.Set("resource", types.JsonRaw(resourceJSON))

	if err := app.Dao().SaveRecord(record); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to save resource"})
	}

	return c.JSON(http.StatusOK, map[string]interface{}{
		"id":       record.Id,
		"resource": record.Get("resource"),
	})
}

// CapabilityStatement endpoint
func getCapabilityStatement(c echo.Context) error {
	capabilityStatement := map[string]interface{}{
		"resourceType": "CapabilityStatement",
		"status":       "active",
		"date":         time.Now().Format(time.RFC3339),
		"fhirVersion":  "4.3.0",
		"kind":         "instance",
		"software": map[string]string{
			"name":    "PocketFHIR Server",
			"version": "0.1.0",
		},
		"implementation": map[string]string{
			"description": "FHIR ANT Server for managing healthcare data",
		},
		"format": []string{"json"},
		"rest": []map[string]interface{}{
			{
				"mode": "server",
				"resource": []map[string]interface{}{
					{
						"type": "Patient",
						"interaction": []map[string]string{
							{"code": "read"},
							{"code": "vread"},
							{"code": "update"},
							{"code": "history-instance"},
						},
					},
				},
			},
		},
	}

	return c.JSON(http.StatusOK, capabilityStatement)
}

// Register FHIR routes
func registerFHIRRoutes(app *pocketbase.PocketBase) {
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		// Register CapabilityStatement endpoint
		e.Router.GET("/api/fhir/metadata", func(c echo.Context) error {
			return getCapabilityStatement(c)
		})

		e.Router.GET("/api/fhir/:resourceType/:id", func(c echo.Context) error {
			return getFHIRResource(c, app)
		})

		e.Router.POST("/api/fhir/:resourceType", func(c echo.Context) error {
			return createOrUpdateFHIRResource(c, app)
		})

		return nil
	})
}
