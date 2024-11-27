package fhirant

// import (
// 	"log"
// 	"os"
// 	"os/signal"
// 	"sync"
// 	"syscall"
// 	"time"

// 	"github.com/caddyserver/caddy/v2"
// 	"github.com/pocketbase/pocketbase"
// 	"github.com/pocketbase/pocketbase/core"
// )

// // Store references to the PocketBase instance and configuration JSON for Caddy
// var pocketBaseApp *pocketbase.PocketBase
// var stopChannel chan os.Signal

// // StartFhirAnt initializes and starts both PocketBase and Caddy servers.
// func StartFhirAnt(
// 	pbPort string, httpPort string, httpsPort string, pbUrl string, ipAddress string, dataDir string, enableApiLogs bool, storagePath string) {

// 	// Set environment variables for PocketBase configuration
// 	log.Println("[DEBUG] Setting environment variables...")
// 	if err := os.Setenv("POCKETBASE_DATA_DIR", dataDir); err != nil {
// 		onPocketBaseError(err)
// 		log.Fatalf("Failed to set data directory: %v", err)
// 	}

// 	// Handle graceful shutdown signal
// 	log.Println("[DEBUG] Setting up channel for graceful shutdown...")
// 	stopChannel = make(chan os.Signal, 1)
// 	signal.Notify(stopChannel, os.Interrupt, syscall.SIGTERM)

// 	// Start the PocketBase server in a separate goroutine
// 	var wg sync.WaitGroup
// 	wg.Add(2)

// 	go func() {
// 		defer wg.Done()
// 		log.Println("[DEBUG] Starting FHIR ANT server...")

// 		// Set up and run PocketBase server
// 		pocketBaseApp = pocketbase.NewWithConfig(pocketbase.Config{
// 			DefaultDataDir:  dataDir,
// 			DefaultDev:      enableApiLogs,
// 			HideStartBanner: false,
// 		})

// 		if err := runServerInstance(pocketBaseApp, pbUrl, pbPort, enableApiLogs); err != nil {
// 			log.Printf("[ERROR] PocketBase failed to start: %v", err)
// 			onPocketBaseError(err)
// 			return
// 		}
// 		onPocketBaseStart()
// 	}()

// 	// Start the Caddy server in a separate goroutine
// 	go func() {
// 		defer wg.Done()
// 		log.Println("[DEBUG] Starting Caddy server with HTTPS...")

// 		// Create the Caddy configuration
// 		caddyConfig := caddyConfig{
// 			PbPort:      pbPort,
// 			HttpPort:    httpPort,
// 			HttpsPort:   httpsPort,
// 			PbUrl:       pbUrl,
// 			StoragePath: storagePath,
// 			IpAddress:   ipAddress,
// 		}

// 		if err := startCaddyInstance(caddyConfig); err != nil {
// 			log.Printf("[ERROR] Caddy failed to start: %v", err)
// 			onCaddyError(err)
// 			return
// 		}
// 		onCaddyStart()
// 	}()

// 	// Wait for interrupt signal to gracefully shut down the servers
// 	log.Println("[DEBUG] Waiting for interrupt signal to shut down the servers...")
// 	<-stopChannel
// 	log.Println("[INFO] Shutting down PocketBase and Caddy servers...")

// 	// Stop both servers gracefully
// 	StopFhirAnt()
// 	wg.Wait()
// 	log.Println("[INFO] PocketBase and Caddy servers shut down gracefully.")
// }

// func StopFhirAnt() {
// 	log.Println("[INFO] Initiating shutdown of PocketBase and Caddy servers...")

// 	// Stop PocketBase with a timeout
// 	done := make(chan struct{})
// 	go func() {
// 		log.Println("[DEBUG] Stopping PocketBase server...")
// 		if pocketBaseApp != nil {
// 			err := pocketBaseApp.OnTerminate().Trigger(&core.TerminateEvent{
// 				App: pocketBaseApp,
// 			}, func(e *core.TerminateEvent) error {
// 				log.Println("[DEBUG] PocketBase shutdown cleanup triggered.")
// 				return nil
// 			})
// 			if err != nil {
// 				log.Printf("[ERROR] Failed to terminate PocketBase: %v", err)
// 				onPocketBaseError(err)
// 			} else {
// 				log.Println("[DEBUG] PocketBase server terminated successfully.")
// 				onPocketBaseStop()
// 			}
// 		}
// 		close(done)
// 	}()

// 	select {
// 	case <-done:
// 		log.Println("[INFO] PocketBase server shut down cleanly.")
// 	case <-time.After(5 * time.Second):
// 		log.Println("[WARN] PocketBase shutdown timed out, proceeding forcefully...")
// 	}

// 	// Stop Caddy Server
// 	log.Println("[DEBUG] Stopping Caddy server...")
// 	if err := caddy.Stop(); err != nil {
// 		log.Printf("[ERROR] Failed to stop Caddy server: %v", err)
// 		onCaddyError(err)
// 	} else {
// 		log.Println("[DEBUG] Caddy server stopped successfully.")
// 		onCaddyStop()
// 	}

// 	log.Println("[INFO] PocketBase and Caddy servers shut down explicitly.")
// }
