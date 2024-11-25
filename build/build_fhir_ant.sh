#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANDROID_OUTPUT_DIR="$WORK_DIR/android-output"

# Debugging paths
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "WORK_DIR=$WORK_DIR"
echo "ANDROID_OUTPUT_DIR=$ANDROID_OUTPUT_DIR"

# Verify OpenSSL and SQLCipher builds
ARCHS=("arm" "arm64" "x86_64")
for ARCH in "${ARCHS[@]}"; do
  echo "Verifying dependencies for $ARCH..."
  ls "$ANDROID_OUTPUT_DIR/openssl/$ARCH/include/openssl/crypto.h"
  ls "$ANDROID_OUTPUT_DIR/openssl/$ARCH/include/openssl/macros.h"
  ls "$ANDROID_OUTPUT_DIR/openssl/$ARCH/lib/libcrypto.so"
  ls "$ANDROID_OUTPUT_DIR/openssl/$ARCH/lib/libssl.so"
  ls "$ANDROID_OUTPUT_DIR/sqlcipher/$ARCH/include/sqlcipher/sqlite3.h"
  ls "$ANDROID_OUTPUT_DIR/sqlcipher/$ARCH/lib/libsqlcipher.so"
done

# Set environment variables for all architectures
export CGO_ENABLED=1
export ANDROID_NDK_HOME="/home/grey/Android/Sdk/ndk/28.0.12433566"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export CGO_CFLAGS="-I$ANDROID_OUTPUT_DIR/openssl/arm64/include -I$ANDROID_OUTPUT_DIR/sqlcipher/arm64/include/sqlcipher"
export CGO_LDFLAGS="-L$ANDROID_OUTPUT_DIR/openssl/arm64/lib -L$ANDROID_OUTPUT_DIR/sqlcipher/arm64/lib -lsqlcipher -lssl -lcrypto -llog"

# Build for all supported architectures in a single AAR
echo "Building FHIR ANT .aar file for Android (all architectures)..."
gomobile bind -tags "cgo" -target=android -androidapi=28 -o fhirant.aar ./fhirant || exit 1

echo "FHIR ANT .aar (multi-architecture) build completed successfully."
