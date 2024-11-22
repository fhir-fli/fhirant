#!/bin/bash

# Navigate to the root directory of the project
cd "$(dirname "$0")/.."

# Clean up previous builds
rm -f pocketfhir_server

# Initialize Go modules in the root directory if go.mod does not exist
if [ ! -f go.mod ]; then
    go mod init pocketfhir
fi

# Tidy up Go modules in the root directory
go mod tidy

# Build the PocketFHIR server for desktop and place the executable in the root directory
echo "Building PocketFHIR for regular platform..."
if ! CGO_ENABLED=0 go build -o pocketfhir_server ./main.go; then
    echo "Build failed!"
    exit 1
fi
echo "Regular PocketFHIR build completed."

# Start the PocketFHIR server in the background (for the regular platform)
./pocketfhir_server serve

echo "PocketFHIR server started."
