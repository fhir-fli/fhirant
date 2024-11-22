#!/bin/bash

# Ensure Go modules are initialized
if [ ! -f go.mod ]; then
    go mod init pocketfhir
fi

# Install necessary tools
go get -u golang.org/x/mobile/bind
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Build PocketFHIR .aar for Android
echo "Building PocketFHIR .aar file for Android..."
gomobile bind -target=android -androidapi=21 -o pocketfhir.aar ./pocketfhir
if [ $? -ne 0 ]; then
    echo "Android build failed!"
    exit 1
fi
mv pocketfhir.aar ../fhir_ant/android/app/libs/pocketfhir.aar
rm pocketfhir-sources.jar

echo "PocketFHIR Android build completed successfully."

