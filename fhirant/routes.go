package fhirant

import (
	"fmt"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
)

// FhirAntAPI struct encapsulates FhirAnt instance and API-related methods.
type FhirAntAPI struct {
	FhirAnt *FhirAnt
}

// NewFhirAntAPI initializes a new FhirAntAPI.
func NewFhirAntAPI(dbPath, encryptionKey string) (*FhirAntAPI, error) {
	fhirAnt, err := NewFhirAnt(dbPath, encryptionKey)
	if err != nil {
		return nil, err
	}
	return &FhirAntAPI{FhirAnt: fhirAnt}, nil
}

// RegisterRoutes sets up all necessary FHIR API routes.
func (api *FhirAntAPI) RegisterRoutes(e *echo.Echo) {
	// CapabilityStatement endpoint
	e.GET("/api/fhir/metadata", api.getCapabilityStatement)

	// CRUD endpoints
	e.GET("/api/fhir/:resourceType/:id", api.getFHIRResource)
	e.POST("/api/fhir/:resourceType", api.createOrUpdateFHIRResource)
	e.PUT("/api/fhir/:resourceType/:id", api.updateFHIRResource)
	e.DELETE("/api/fhir/:resourceType/:id", api.deleteFHIRResource)
}

// getFHIRResource handles GET requests to fetch a FHIR resource by ID.
func (api *FhirAntAPI) getFHIRResource(c echo.Context) error {
	resourceType := c.Param("resourceType")
	id := c.Param("id")

	resource, err := api.FhirAnt.GetResource(resourceType, id)
	if err != nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "Resource not found"})
	}

	return c.JSON(http.StatusOK, resource)
}

// createOrUpdateFHIRResource handles POST requests to create or update a FHIR resource.
func (api *FhirAntAPI) createOrUpdateFHIRResource(c echo.Context) error {
	resourceType := c.Param("resourceType")

	var resourceData map[string]interface{}
	if err := c.Bind(&resourceData); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid JSON data"})
	}

	resourceID, ok := resourceData["id"].(string)
	if !ok || resourceID == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Resource ID is required"})
	}

	if err := api.FhirAnt.CreateResource(resourceType, resourceID, resourceData); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("Failed to create or update resource: %v", err)})
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"id": resourceID, "resource": resourceData})
}

// updateFHIRResource handles PUT requests to update a FHIR resource by ID.
func (api *FhirAntAPI) updateFHIRResource(c echo.Context) error {
	resourceType := c.Param("resourceType")
	id := c.Param("id")

	var resourceData map[string]interface{}
	if err := c.Bind(&resourceData); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid JSON data"})
	}

	if err := api.FhirAnt.UpdateResource(resourceType, id, resourceData); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("Failed to update resource: %v", err)})
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"id": id, "resource": resourceData})
}

// deleteFHIRResource handles DELETE requests to remove a FHIR resource by ID.
func (api *FhirAntAPI) deleteFHIRResource(c echo.Context) error {
	resourceType := c.Param("resourceType")
	id := c.Param("id")

	if err := api.FhirAnt.DeleteResource(resourceType, id); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": fmt.Sprintf("Failed to delete resource: %v", err)})
	}

	return c.JSON(http.StatusOK, map[string]string{"message": "Resource deleted successfully"})
}

// getCapabilityStatement handles requests for the FHIR CapabilityStatement.
func (api *FhirAntAPI) getCapabilityStatement(c echo.Context) error {
	capabilityStatement := map[string]interface{}{
		"resourceType":   "CapabilityStatement",
		"status":         "active",
		"date":           time.Now().Format(time.RFC3339),
		"fhirVersion":    "4.3.0",
		"kind":           "instance",
		"software":       map[string]string{"name": "FHIR ANT Server", "version": "0.1.0"},
		"implementation": map[string]string{"description": "FHIR ANT Server for managing healthcare data"},
		"format":         []string{"json"},
		"rest": []map[string]interface{}{
			{
				"mode": "server",
				"resource": []map[string]interface{}{
					{
						"type":        "Patient",
						"interaction": []map[string]string{{"code": "read"}, {"code": "vread"}, {"code": "update"}, {"code": "history-instance"}},
					},
				},
			},
		},
	}

	return c.JSON(http.StatusOK, capabilityStatement)
}

// Close cleans up resources and closes the database connection.
func (api *FhirAntAPI) Close() {
	api.FhirAnt.Close()
}
