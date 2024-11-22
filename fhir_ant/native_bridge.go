package pocketfhir

import (
	"log"
)

// Java Callbacks, make sure to register them before starting PocketBase
// to expose any method to Java, add that with FirstLetterCapital
var nativeBridge NativeBridge

// RegisterNativeBridgeCallback allows setting the NativeBridge interface for callbacks
func RegisterNativeBridgeCallback(c NativeBridge) {
	nativeBridge = c
}

// NativeBridge interface to define the methods used for native callbacks
type NativeBridge interface {
	HandleCallback(command string, data string) string
}

// sendCommand sends command to native and returns the response
func sendCommand(command string, data string) string {
	if nativeBridge != nil {
		log.Printf("[DEBUG] Sending command '%s' with data: %s", command, data)
		return nativeBridge.HandleCallback(command, data)
	}
	log.Printf("[DEBUG] No NativeBridge defined. Command '%s' not sent.", command)
	return ""
}

// sendHealthUpdate sends an update to the native layer regarding the health of servers (PocketBase/Caddy).
func sendHealthUpdate(healthStatus string) {
	if nativeBridge != nil {
		log.Printf("[DEBUG] Sending health update: %s", healthStatus)
		nativeBridge.HandleCallback("HealthUpdate", healthStatus)
	} else {
		log.Printf("[DEBUG] No NativeBridge defined. Health update '%s' not sent.", healthStatus)
	}
}

// This function will be triggered when starting PocketBase
func onPocketBaseStart() {
	sendHealthUpdate("PocketBase server started successfully.")
}

// This function will be triggered when stopping PocketBase
func onPocketBaseStop() {
	sendHealthUpdate("PocketBase server stopped successfully.")
}

// This function will be triggered when starting Caddy
func onCaddyStart() {
	sendHealthUpdate("Caddy server started successfully.")
}

// This function will be triggered when stopping Caddy
func onCaddyStop() {
	sendHealthUpdate("Caddy server stopped successfully.")
}

// This function will be triggered if there's an error with PocketBase
func onPocketBaseError(err error) {
	sendHealthUpdate("PocketBase server encountered an error: " + err.Error())
}

// This function will be triggered if there's an error with Caddy
func onCaddyError(err error) {
	sendHealthUpdate("Caddy server encountered an error: " + err.Error())
}
