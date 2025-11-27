#!/bin/bash

# FHIR ANT Server Start Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8080
DB_PATH="$SCRIPT_DIR/data/fhir.db"
HTTPS=false
CERT_PATH="$SCRIPT_DIR/assets/cert.pem"
KEY_PATH="$SCRIPT_DIR/assets/key.pem"

# Detect platform and set SQLCipher path
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  SQLCIPHER_PATH="$SCRIPT_DIR/lib/sqlcipher/linux/libsqlcipher.so"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  SQLCIPHER_PATH="$SCRIPT_DIR/lib/sqlcipher/macos/libsqlcipher.dylib"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
  SQLCIPHER_PATH="$SCRIPT_DIR/lib/sqlcipher/windows/sqlcipher.dll"
else
  echo "Unsupported platform: $OSTYPE"
  exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --port=*)
      PORT="${1#*=}"
      shift
      ;;
    --db-path=*)
      DB_PATH="${1#*=}"
      shift
      ;;
    --sqlcipher-path=*)
      SQLCIPHER_PATH="${1#*=}"
      shift
      ;;
    --https)
      HTTPS=true
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --port=NUMBER        Server port (default: 8080)"
      echo "  --db-path=PATH       Database path (default: ./data/fhir.db)"
      echo "  --sqlcipher-path=PATH Path to SQLCipher library (auto-detected by default)"
      echo "  --https              Enable HTTPS using certificates in assets/cert.pem and assets/key.pem"
      echo "  --help               Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Ensure data directory exists
mkdir -p "$(dirname "$DB_PATH")"

# Verify SQLCipher exists
if [ ! -f "$SQLCIPHER_PATH" ]; then
  echo "Error: SQLCipher library not found at $SQLCIPHER_PATH"
  echo "Run the get_sqlcipher.sh script first or specify custom path with --sqlcipher-path"
  exit 1
fi

# Start server
echo "Starting FHIR ANT Server..."
echo "Port: $PORT"
echo "Database: $DB_PATH"
echo "SQLCipher: $SQLCIPHER_PATH"

if [ "$HTTPS" = true ]; then
  # Verify certificate and key exist
  if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Error: HTTPS certificate or key not found in assets directory"
    exit 1
  fi
  echo "HTTPS: Enabled"
  echo "Certificate: $CERT_PATH"
  echo "Private Key: $KEY_PATH"
  CMD="dart $SCRIPT_DIR/bin/server.dart --port=$PORT --db-path=$DB_PATH --sqlcipher-path=$SQLCIPHER_PATH --https --cert-path=$CERT_PATH --key-path=$KEY_PATH"
else
  echo "HTTPS: Disabled"
  CMD="dart $SCRIPT_DIR/bin/server.dart --port=$PORT --db-path=$DB_PATH --sqlcipher-path=$SQLCIPHER_PATH"
fi

echo "Command: $CMD"
eval "$CMD"