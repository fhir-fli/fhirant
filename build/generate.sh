#!/bin/bash

# Navigate to the root directory of the project
cd "$(dirname "$0")/.."

# Clean up previous builds
rm -f fhirant

# Initialize Go modules in the root directory if go.mod does not exist
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Tidy up Go modules in the root directory
go mod tidy

# Build the PocketBase server and place the executable in the root directory
CGO_ENABLED=0 go build -o fhirant ./src

# Start the PocketBase server in the background
./fhirant serve &
PB_PID=$!

# Wait for the pb_migrations and pb_data directories to be generated
while [ ! -d "./pb_migrations" ] || [ ! -d "./pb_data" ]; do
  echo "Waiting for pb_migrations and pb_data directories to be generated..."
  sleep 2
done

# Stop the PocketBase server
kill $PB_PID

sleep 1

# Copy the generated directories to the data directory
cp -r ./pb_migrations ./data/pb_migrations
cp -r ./pb_data ./data/pb_data

rm -r ./pb_migrations
rm -r ./pb_data

echo "FHIR ANT build completed successfully."
