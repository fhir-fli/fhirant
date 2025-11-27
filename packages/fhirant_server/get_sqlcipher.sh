#!/bin/bash

# SQLCipher Download Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLCIPHER_DIR="$SCRIPT_DIR/lib/sqlcipher"

# Create directories
mkdir -p "$SQLCIPHER_DIR/linux"
mkdir -p "$SQLCIPHER_DIR/macos"
mkdir -p "$SQLCIPHER_DIR/windows"

echo "Setting up SQLCipher libraries..."

# For Linux, build from source
if [ ! -f "$SQLCIPHER_DIR/linux/libsqlcipher.so" ]; then
  echo "Building SQLCipher for Linux..."
  
  # Install dependencies
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y build-essential libssl-dev tcl-dev
  elif command -v yum &> /dev/null; then
    sudo yum install -y gcc make openssl-devel tcl-devel
  fi
  
  # Download and build
  TMP_DIR=$(mktemp -d)
  cd "$TMP_DIR"
  curl -L "https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.5.5.tar.gz" -o sqlcipher.tar.gz
  tar xzf sqlcipher.tar.gz
  cd sqlcipher-*
  
  ./configure --enable-tempstore=yes CFLAGS="-DSQLITE_HAS_CODEC" LDFLAGS="-lcrypto"
  make
  cp .libs/libsqlcipher.so "$SQLCIPHER_DIR/linux/"
  cd "$SCRIPT_DIR"
  rm -rf "$TMP_DIR"
  echo "Linux SQLCipher library built in $SQLCIPHER_DIR/linux/"
fi

# Print instructions for macOS and Windows
echo ""
echo "For macOS: Run 'brew install sqlcipher' and copy the library:"
echo "  cp \$(brew --prefix sqlcipher)/lib/libsqlcipher.dylib $SQLCIPHER_DIR/macos/"
echo ""
echo "For Windows: Download from https://www.zetetic.net/sqlcipher/open-source/"
echo "  and copy sqlcipher.dll to $SQLCIPHER_DIR/windows/"