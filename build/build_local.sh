#!/bin/bash

# Navigate to the root directory of the project
cd "$(dirname "$0")/.."

# Define the folder name
FOLDER="storage"

# Remove the storage folder if it exists
rm -r $FOLDER

# Check if the folder already exists
if [ ! -d "$FOLDER" ]; then
  echo "Folder '$FOLDER' does not exist. Creating it now..."
  mkdir "$FOLDER"
else
  echo "Folder '$FOLDER' already exists."
fi

# Clean up previous builds
rm -f fhirant_server

# Initialize Go modules in the root directory if go.mod does not exist
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Tidy up Go modules in the root directory
go mod tidy

# Set environment variables for SQLCipher
export CGO_CFLAGS="-I/usr/include/sqlcipher"
export CGO_LDFLAGS="-L/usr/lib -lsqlcipher -lcrypto"

# Build the FHIR ANT server for desktop and place the executable in the root directory
echo "Building FHIR ANT for regular platform with SQLCipher..."
if ! CGO_ENABLED=1 go build -tags "cgo" -o fhirant_server ./main.go; then
    echo "Build failed!"
    exit 1
fi
echo "Regular FHIR ANT build with SQLCipher completed."

# Start the FHIR ANT server in the background (for the regular platform)
./fhirant_server serve

echo "FHIR ANT server started."
