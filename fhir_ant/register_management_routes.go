package pocketfhir

import (
	"net/http"

	"github.com/labstack/echo/v5"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

// Register additional server management routes
func registerManagementRoutes(app *pocketbase.PocketBase) {
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		// Health check endpoint
		e.Router.GET("/api/status", func(c echo.Context) error {
			return c.JSON(http.StatusOK, map[string]string{
				"status": "running",
			})
		})

		// Version endpoint
		e.Router.GET("/api/version", func(c echo.Context) error {
			return c.JSON(http.StatusOK, map[string]string{
				"version": "0.1.0",
			})
		})

		return nil
	})
}
