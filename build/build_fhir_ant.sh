#!/bin/bash

# Ensure Go modules are initialized
if [ ! -f go.mod ]; then
    go mod init fhirant
fi

# Install necessary tools
go get -u golang.org/x/mobile/bind
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init

# Build FHIR ANT .aar for Android
echo "Building FHIR ANT .aar file for Android..."
gomobile bind -target=android -androidapi=21 -o fhirant.aar ./fhirant
if [ $? -ne 0 ]; then
    echo "Android build failed!"
    exit 1
fi
mv fhirant.aar ../fhir_ant_mobile/android/app/libs/fhirant.aar
rm fhirant-sources.jar

cd ../fhir_ant_mobile

# Define the file path
FILE_PATH="./android/app/build.gradle"

# Use sed to replace the specified line
sed -i.bak "s/implementation(name: 'fhirant', ext: 'aar') \/\/ Include FHIR ANT \.aar/implementation(name: 'fhirant-2', ext: 'aar') \/\/ Include FHIR ANT \.aar/" "$FILE_PATH"

flutter clean ; flutter pub get ; flutter build apk

sed -i.bak "s/implementation(name: 'fhirant-2', ext: 'aar') \/\/ Include FHIR ANT \.aar/implementation(name: 'fhirant', ext: 'aar') \/\/ Include FHIR ANT \.aar/" "$FILE_PATH"

flutter clean ; flutter pub get ; flutter build apk

cd ../fhirant