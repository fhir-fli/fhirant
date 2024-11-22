#!/bin/bash

# Navigate to the root directory of the project
cd "$(dirname "$0")/.."

# Clean up previous builds
rm -f fhirant_server

# Initialize Go modules in the root directory if go.mod does not exist
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Tidy up Go modules in the root directory
go mod tidy

# Build the FHIR ANT server for desktop and place the executable in the root directory
echo "Building FHIR ANT for regular platform..."
if ! CGO_ENABLED=0 go build -o fhirant_server ./main.go; then
    echo "Build failed!"
    exit 1
fi
echo "Regular FHIR ANT build completed."

# Start the FHIR ANT server in the background (for the regular platform)
./fhirant_server serve

echo "FHIR ANT server started."
