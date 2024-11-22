package pocketfhir

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/labstack/echo/v5"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

// runServerInstance handles the setup and running of the PocketBase server instance.
func runServerInstance(app *pocketbase.PocketBase, ipAddress, pbPort string, enableApiLogs bool) error {
	// Set CLI-like arguments for PocketBase to specify server address and port
	log.Printf("[DEBUG] Setting CLI arguments for server address and port: %s:%s\n", ipAddress, pbPort)
	os.Args = []string{os.Args[0], "serve", "--http", fmt.Sprintf("%s:%s", ipAddress, pbPort)}

	// Standard setup for the app
	log.Println("[DEBUG] Running standard setup for PocketBase...")
	standard(app)
	log.Println("[DEBUG] Standard setup for PocketBase app completed.")

	// Register hooks, FHIR routes, and management routes
	registerHooks(app)
	registerFHIRRoutes(app)
	registerManagementRoutes(app)
	setupPocketbaseCallbacks(app, enableApiLogs)

	// Initialize collections if necessary
	if err := initializeCollections(app); err != nil {
		log.Printf("[ERROR] Failed to initialize collections: %v", err)
		return err
	}

	// Start the server
	log.Println("[DEBUG] Starting PocketBase server instance...")
	if err := app.Start(); err != nil {
		log.Fatalf("[ERROR] Failed to start PocketBase server: %v", err)
		return err
	}
	return nil
}

// setupPocketbaseCallbacks sets up additional callbacks and native routes for PocketBase
func setupPocketbaseCallbacks(app *pocketbase.PocketBase, enableApiLogs bool) {
	setupOnBeforeServe(app, enableApiLogs)
	setupOnBeforeBootstrap(app)
	setupOnAfterBootstrap(app)
	setupOnTerminate(app)
}

func setupOnBeforeServe(app *pocketbase.PocketBase, enableApiLogs bool) {
	log.Println("[DEBUG] Setting up OnBeforeServe callback...")
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		log.Println("[DEBUG] OnBeforeServe triggered.")
		sendCommand("OnBeforeServe", "")
		if enableApiLogs {
			log.Println("[DEBUG] Adding API logs middleware...")
			e.Router.Use(ApiLogsMiddleWare(app))
		}

		setupNativeGetHandler(e.Router)
		setupNativePostHandler(e.Router)
		return nil
	})
}

func setupNativeGetHandler(router *echo.Echo) {
	log.Println("[DEBUG] Adding native GET request handler...")
	router.AddRoute(echo.Route{
		Method: http.MethodGet,
		Path:   "/api/nativeGet",
		Handler: func(context echo.Context) error {
			log.Println("[DEBUG] Handling native GET request...")
			data := sendCommand("nativeGetRequest", context.QueryParams().Encode())
			return context.JSON(http.StatusOK, map[string]string{"success": data})
		},
	})
}

func setupNativePostHandler(router *echo.Echo) {
	log.Println("[DEBUG] Adding native POST request handler...")
	router.AddRoute(echo.Route{
		Method: http.MethodPost,
		Path:   "/api/nativePost",
		Handler: func(context echo.Context) error {
			log.Println("[DEBUG] Handling native POST request...")
			form, err := context.FormValues()
			if err != nil {
				return context.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
			}
			data := sendCommand("nativePostRequest", form.Encode())
			return context.JSON(http.StatusOK, map[string]string{"success": data})
		},
	})
}

func setupOnBeforeBootstrap(app *pocketbase.PocketBase) {
	log.Println("[DEBUG] Setting up OnBeforeBootstrap callback...")
	app.OnBeforeBootstrap().Add(func(e *core.BootstrapEvent) error {
		log.Println("[DEBUG] OnBeforeBootstrap triggered.")
		sendCommand("OnBeforeBootstrap", "")
		return nil
	})
}

func setupOnAfterBootstrap(app *pocketbase.PocketBase) {
	log.Println("[DEBUG] Setting up OnAfterBootstrap callback...")
	app.OnAfterBootstrap().Add(func(e *core.BootstrapEvent) error {
		log.Println("[DEBUG] OnAfterBootstrap triggered.")
		sendCommand("OnAfterBootstrap", "")
		return nil
	})
}

func setupOnTerminate(app *pocketbase.PocketBase) {
	log.Println("[DEBUG] Setting up OnTerminate callback...")
	app.OnTerminate().Add(func(e *core.TerminateEvent) error {
		log.Println("[DEBUG] OnTerminate triggered.")
		sendCommand("OnTerminate", "")
		return nil
	})
}

// ApiLogsMiddleWare logs all API calls for PocketBase
var requestLogBuffer []string
var mu sync.Mutex

func init() {
	// Background goroutine to batch log requests
	go func() {
		for {
			time.Sleep(1 * time.Second)
			mu.Lock()
			if len(requestLogBuffer) > 0 {
				log.Println("[DEBUG] Batch API request logs:", requestLogBuffer)
				requestLogBuffer = []string{} // Clear the buffer
			}
			mu.Unlock()
		}
	}()
}

func ApiLogsMiddleWare(app core.App) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			request := c.Request()
			fullPath := request.URL.Host + request.URL.Path + "?" + request.URL.RawQuery
			mu.Lock()
			requestLogBuffer = append(requestLogBuffer, fullPath)
			mu.Unlock()
			return next(c)
		}
	}
}
