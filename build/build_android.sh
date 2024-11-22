#!/bin/bash

# Ensure Go modules are initialized
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Install necessary tools
go get -u golang.org/x/mobile/bind
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Build fhirant.aar for Android
echo "Building FHIR ANT .aar file for Android..."
gomobile bind -target=android -androidapi=21 -o fhirant.aar ./fhirant
if [ $? -ne 0 ]; then
    echo "Android build failed!"
    exit 1
fi
mv fhirant.aar ../fhir_ant/android/app/libs/fhirant.aar
rm fhirant-sources.jar

echo "FHIR ANT Android build completed successfully."

