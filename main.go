package main

import "github.com/fhir-fli/fhir_ant/fhir_ant"

func main() {
	// Configuration for local development
	dataDir := "./assets"         // The directory to use for PocketBase data
	pbIpAddress := "127.0.0.1"    // PocketBase IP address for local development
	caddyIpAddress := "127.0.0.1" // Caddy server loopback IP address to prevent conflict
	pbPort := "8090"              // PocketBase port set to 8090
	httpPort := "8081"            // Caddy HTTP traffic port
	httpsPort := "8443"           // Caddy HTTPS traffic port
	enableApiLogs := true         // Enable API logs for detailed local debugging
	storagePath := "./storage"    // Local storage path for Caddy

	// Start PocketFHIR server with local development configuration
	pocketfhir.StartPocketFHIR(pbPort, httpPort, httpsPort, pbIpAddress, caddyIpAddress, dataDir, enableApiLogs, storagePath)
}
