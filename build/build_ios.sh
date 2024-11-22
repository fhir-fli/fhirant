#!/bin/bash

# Ensure Go modules are initialized
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Install necessary tools
go get -u golang.org/x/mobile/bind
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Build FHIR ANT .framework for iOS
echo "Building FHIR ANT .framework for iOS..."
gomobile bind -target=ios -o fhirant.xcframework ./fhirant
if [ $? -ne 0 ]; then
    echo "iOS build failed!"
    exit 1
fi

# Move the framework to the appropriate iOS directory
mv fhirant.xcframework ../fhir_ant/ios/libs/fhirant.xcframework

echo "FHIR ANT iOS build completed successfully."
