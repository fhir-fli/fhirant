package fhirant

import (
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/caddyserver/caddy/v2"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
)

// Store references to the PocketBase instance and configuration JSON for Caddy
var pocketBaseApp *pocketbase.PocketBase
var stopChannel chan os.Signal

func StartFhirAnt(
	pbPort string, httpPort string, httpsPort string, pbUrl string, ipAddress string, dataDir string, enableApiLogs bool, storagePath string) {

	// Set environment variables for PocketBase configuration
	log.Println("[DEBUG] Setting environment variables...")
	if err := os.Setenv("POCKETBASE_DATA_DIR", dataDir); err != nil {
		log.Fatalf("[ERROR] Failed to set data directory: %v", err)
	}

	// Set up signal handling for graceful shutdown
	log.Println("[DEBUG] Setting up channel for graceful shutdown...")
	stopChannel = make(chan os.Signal, 1)
	signal.Notify(stopChannel, os.Interrupt, syscall.SIGTERM)

	var wg sync.WaitGroup
	wg.Add(2) // We need to wait for two goroutines to complete: PocketBase and Caddy

	// Start the PocketBase server in a separate goroutine
	go func() {
		defer wg.Done()
		log.Println("[DEBUG] Starting PocketBase server...")

		config := pocketbase.Config{
			DefaultDataDir:  dataDir,
			DefaultDev:      enableApiLogs,
			HideStartBanner: false,
		}

		pocketBaseApp = pocketbase.NewWithConfig(config)

		if err := runServerInstance(pocketBaseApp, pbUrl, pbPort, enableApiLogs); err != nil {
			log.Printf("[ERROR] PocketBase failed to start: %v", err)
			return
		}
		log.Println("[INFO] PocketBase started successfully.")
	}()

	// Start the Caddy server in a separate goroutine
	go func() {
		defer wg.Done()
		log.Println("[DEBUG] Starting Caddy server...")

		caddyConfig := caddyConfig{
			PbPort:      pbPort,
			HttpPort:    httpPort,
			HttpsPort:   httpsPort,
			PbUrl:       pbUrl,
			StoragePath: storagePath,
			IpAddress:   ipAddress,
		}

		if err := startCaddyInstance(caddyConfig); err != nil {
			log.Printf("[ERROR] Caddy failed to start: %v", err)
			return
		}
		log.Println("[INFO] Caddy started successfully.")
	}()

	// Wait for shutdown signal
	log.Println("[DEBUG] Waiting for interrupt signal to shut down the servers...")
	<-stopChannel
	log.Println("[INFO] Shutdown signal received. Initiating shutdown of both servers...")

	// Initiate shutdown for both PocketBase and Caddy
	StopFhirAnt()

	// Wait for both servers to shut down properly
	wg.Wait()
	log.Println("[INFO] Both PocketBase and Caddy servers shut down gracefully.")
}

// StopFhirAnt gracefully stops both PocketBase and Caddy servers.
func StopFhirAnt() {
	log.Println("[INFO] Initiating shutdown of PocketBase and Caddy servers...")

	var wg sync.WaitGroup
	wg.Add(2)

	// Stop Caddy Server first
	go func() {
		defer wg.Done()
		log.Println("[DEBUG] Stopping Caddy server...")

		if err := caddy.Stop(); err != nil {
			log.Printf("[ERROR] Failed to stop Caddy server: %v", err)
		} else {
			log.Println("[INFO] Caddy server stopped successfully.")
		}
	}()

	// Stop PocketBase Server
	go func() {
		defer wg.Done()
		log.Println("[DEBUG] Stopping PocketBase server...")

		if pocketBaseApp != nil {
			err := pocketBaseApp.OnTerminate().Trigger(&core.TerminateEvent{
				App: pocketBaseApp,
			}, func(e *core.TerminateEvent) error {
				log.Println("[DEBUG] PocketBase shutdown cleanup triggered.")
				return nil
			})

			if err != nil {
				log.Printf("[ERROR] Failed to terminate PocketBase: %v", err)
			} else {
				log.Println("[INFO] PocketBase server terminated successfully.")
			}
		}
	}()

	// Wait for both to complete
	wg.Wait()

	log.Println("[INFO] PocketBase and Caddy servers have shut down explicitly.")
}
