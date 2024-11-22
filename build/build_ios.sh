#!/bin/bash

# Ensure Go modules are initialized
if [ ! -f go.mod ]; then
    go mod init pocketfhir
fi

# Install necessary tools
go get -u golang.org/x/mobile/bind
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Build PocketFHIR .framework for iOS
echo "Building PocketFHIR .framework for iOS..."
gomobile bind -target=ios -o pocketfhir.xcframework ./pocketfhir
if [ $? -ne 0 ]; then
    echo "iOS build failed!"
    exit 1
fi

# Move the framework to the appropriate iOS directory
mv pocketfhir.xcframework ../fhir_ant/ios/libs/pocketfhir.xcframework

echo "PocketFHIR iOS build completed successfully."
