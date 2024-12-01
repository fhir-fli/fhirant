package main

import (
	"fhirant/api"
	"fhirant/couchbase"
	"log"
	"net/http"
)

func main() {
    // Initialize Couchbase Connection
    err := couchbase.InitCouchbaseConnection()
    if err != nil {
        log.Fatalf("Could not initialize Couchbase connection: %v", err)
    }

    // Set up HTTP routes
    http.HandleFunc("/status", api.StatusHandler)
    http.HandleFunc("/resource/create", api.CreateResourceHandler)

    // Start the server
    log.Println("Starting server on :8080")
    if err := http.ListenAndServe(":8080", nil); err != nil {
        log.Fatal("Failed to start server:", err)
    }
}
