#!/bin/bash

WORK_DIR="$HOME/dev/fhir/fhirant"
OPENSSL_DIR="$WORK_DIR/openssl"
SQLCIPHER_DIR="$WORK_DIR/sqlcipher"
ANDROID_OUTPUT_DIR="$WORK_DIR/android-output"

# Set Android NDK paths
export ANDROID_NDK_HOME="/home/grey/Android/Sdk/ndk/28.0.12433566"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# Android architectures
ARCHS=("arm" "arm64" "x86" "x86_64")

declare -A ARCH_CC=(
  ["arm"]="armv7a-linux-androideabi28-clang"
  ["arm64"]="aarch64-linux-android28-clang"
  ["x86"]="i686-linux-android28-clang"
  ["x86_64"]="x86_64-linux-android28-clang"
)

declare -A ARCH_CXX=(
  ["arm"]="armv7a-linux-androideabi28-clang++"
  ["arm64"]="aarch64-linux-android28-clang++"
  ["x86"]="i686-linux-android28-clang++"
  ["x86_64"]="x86_64-linux-android28-clang++"
)

# Clone OpenSSL if not present
if [ ! -d "$OPENSSL_DIR" ]; then
  git clone --depth 1 https://github.com/openssl/openssl.git "$OPENSSL_DIR"
fi

# Clone SQLCipher if not present
if [ ! -d "$SQLCIPHER_DIR" ]; then
  git clone --depth 1 https://github.com/sqlcipher/sqlcipher.git "$SQLCIPHER_DIR"
fi

# Build OpenSSL for each architecture
for ARCH in "${ARCHS[@]}"; do
  echo "Building OpenSSL for $ARCH..."
  
  export CC="${ARCH_CC[$ARCH]}"
  export CXX="${ARCH_CXX[$ARCH]}"
  OUTPUT_DIR="$ANDROID_OUTPUT_DIR/openssl/$ARCH"

  mkdir -p "$OUTPUT_DIR"

  cd "$OPENSSL_DIR" || exit
  make clean || true
  ./Configure "android-$ARCH" shared no-asm no-dtls no-dtls1 --prefix="$OUTPUT_DIR" || exit 1
  make -j$(nproc) > "$OUTPUT_DIR/build.log" 2>&1 || { echo "OpenSSL build failed for $ARCH. Check logs."; exit 1; }
  make install_sw > "$OUTPUT_DIR/install.log" 2>&1 || { echo "OpenSSL install failed for $ARCH. Check logs."; exit 1; }

  echo "OpenSSL built for $ARCH and installed to $OUTPUT_DIR"
done

# Build SQLCipher for each architecture
for ARCH in "${ARCHS[@]}"; do
  echo "Building SQLCipher for $ARCH..."

  export CC="${ARCH_CC[$ARCH]}"
  export CXX="${ARCH_CXX[$ARCH]}"
  OPENSSL_OUTPUT_DIR="$ANDROID_OUTPUT_DIR/openssl/$ARCH"
  OUTPUT_DIR="$ANDROID_OUTPUT_DIR/sqlcipher/$ARCH"

  mkdir -p "$OUTPUT_DIR"

  cd "$SQLCIPHER_DIR" || exit
  make clean || true
  ./configure --host="${ARCH_CC[$ARCH]%28-clang}" --enable-tempstore=yes --with-crypto-lib="openssl" \
    CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_ENABLE_JSON1=1 -I$OPENSSL_OUTPUT_DIR/include" \
    LDFLAGS="-L$OPENSSL_OUTPUT_DIR/lib -lssl -lcrypto -llog" --prefix="$OUTPUT_DIR" || exit 1
  make -j$(nproc) > "$OUTPUT_DIR/build.log" 2>&1 || { echo "SQLCipher build failed for $ARCH. Check logs."; exit 1; }
  make install > "$OUTPUT_DIR/install.log" 2>&1 || { echo "SQLCipher install failed for $ARCH. Check logs."; exit 1; }

  echo "SQLCipher built for $ARCH and installed to $OUTPUT_DIR"
done

echo "OpenSSL and SQLCipher have been built for all architectures."
