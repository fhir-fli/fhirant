package pocketfhir

import (
	"log"
	"sync"
	"time"

	"github.com/labstack/echo/v5"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/models"
	"golang.org/x/net/websocket"
)

var (
	// Clients holds the connected WebSocket clients
	clients   = make(map[*websocket.Conn]bool)
	clientsMu sync.Mutex
)

// Register custom hooks
func registerHooks(app *pocketbase.PocketBase) {
	// Register middleware to log each request
	registerRequestLoggingHook(app)

	// Setup versioning and history hooks
	setupHooks(app)

	// Register WebSocket endpoint for live updates
	registerWebSocketEndpoint(app)
}

// Log each request
func registerRequestLoggingHook(app *pocketbase.PocketBase) {
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		e.Router.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
			return func(c echo.Context) error {
				log.Printf("[INFO] Request: %s %s", c.Request().Method, c.Request().URL.Path)
				return next(c)
			}
		})
		return nil
	})
}

// Setup hooks for resource versioning and history
func setupHooks(app *pocketbase.PocketBase) {
	// Hook for handling resource creation
	app.OnRecordAfterCreateRequest().Add(func(e *core.RecordCreateEvent) error {
		err := handleResourceCreation(app, e)
		if err == nil {
			broadcastWebSocketMessage("created", e.Record)
		}
		return err
	})

	// Hook for handling resource updates
	app.OnRecordBeforeUpdateRequest().Add(func(e *core.RecordUpdateEvent) error {
		err := handleResourceUpdate(app, e)
		if err == nil {
			broadcastWebSocketMessage("updated", e.Record)
		}
		return err
	})

	// Hook for handling resource deletion
	app.OnRecordAfterDeleteRequest().Add(func(e *core.RecordDeleteEvent) error {
		broadcastWebSocketMessage("deleted", e.Record)
		return nil
	})
}

// Register WebSocket endpoint for live updates
func registerWebSocketEndpoint(app *pocketbase.PocketBase) {
	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		e.Router.GET("/ws/live-updates", func(c echo.Context) error {
			websocket.Handler(func(ws *websocket.Conn) {
				clientsMu.Lock()
				clients[ws] = true
				clientsMu.Unlock()

				defer func() {
					clientsMu.Lock()
					delete(clients, ws)
					clientsMu.Unlock()
					_ = ws.Close()
					log.Println("[INFO] WebSocket connection closed")
				}()

				log.Println("[INFO] New WebSocket connection established")

				// Heartbeat mechanism to keep the connection alive
				heartbeatTicker := time.NewTicker(30 * time.Second)
				defer heartbeatTicker.Stop()

				for {
					select {
					case <-heartbeatTicker.C:
						if err := ws.SetDeadline(time.Now().Add(35 * time.Second)); err != nil {
							log.Printf("[ERROR] Failed to set deadline for WebSocket: %v", err)
							return
						}
						if _, err := ws.Write([]byte("ping")); err != nil {
							log.Printf("[ERROR] Failed to send heartbeat: %v", err)
							return
						}
					case <-c.Request().Context().Done():
						// Handle client disconnection gracefully
						log.Println("[INFO] WebSocket client disconnected")
						return
					}
				}
			}).ServeHTTP(c.Response(), c.Request())
			return nil
		})
		return nil
	})
}

// Broadcast a message to all connected WebSocket clients
func broadcastWebSocketMessage(eventType string, record *models.Record) {
	clientsMu.Lock()
	clientsSnapshot := make([]*websocket.Conn, 0, len(clients))
	for client := range clients {
		clientsSnapshot = append(clientsSnapshot, client)
	}
	clientsMu.Unlock()

	message := map[string]interface{}{
		"type":     eventType,
		"record":   record,
		"resource": record.Get("resource"),
	}

	for _, client := range clientsSnapshot {
		go func(client *websocket.Conn) {
			if err := websocket.JSON.Send(client, message); err != nil {
				log.Printf("[ERROR] Failed to send WebSocket message: %v", err)
				clientsMu.Lock()
				delete(clients, client)
				clientsMu.Unlock()
				_ = client.Close()
			}
		}(client)
	}
}
