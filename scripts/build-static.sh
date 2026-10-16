#!/usr/bin/env bash
set -euo pipefail

# Build a statically-linked iperf3 binary using musl libc.
# Usage: IPERF_VERSION=3.17.1 ./build-static.sh

IPERF_VERSION="${IPERF_VERSION:-}"
if [[ -z "$IPERF_VERSION" ]]; then
  echo "ERROR: IPERF_VERSION is not set" >&2
  exit 1
fi

# Upstream iperf tags do not have a 'v' prefix (e.g. 3.22, 3.16-beta1).
VERSION="$IPERF_VERSION"

echo "=== Building static iperf3 ${VERSION} ==="

# Install build dependencies
if command -v apt-get >/dev/null 2>&1; then
  echo "=== Installing dependencies via apt-get ==="
  apt-get update -qq
  apt-get install -y -qq build-essential git musl-tools autoconf automake libtool
elif command -v apk >/dev/null 2>&1; then
  echo "=== Installing dependencies via apk ==="
  apk add --no-cache build-base git autoconf automake libtool
else
  echo "ERROR: No supported package manager found" >&2
  exit 1
fi

# Clean up any previous build
BUILD_DIR="$(pwd)/iperf3-build-static"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== Cloning iperf3 ${VERSION} ==="
git clone --branch "${VERSION}" --depth 1 https://github.com/esnet/iperf.git

cd iperf

echo "=== Bootstrapping build system ==="
autoreconf -fi

echo "=== Configuring static build ==="
./configure CC=musl-gcc CFLAGS="-static" LDFLAGS="-static" --disable-shared --enable-static-bin

echo "=== Building ==="
make -j"$(nproc)"

echo "=== Verifying static linkage ==="
ldd_output=$(ldd src/iperf3 2>&1 || true)
if echo "$ldd_output" | grep -q "not a dynamic executable"; then
  echo "OK: binary is statically linked"
else
  echo "ERROR: binary is not statically linked" >&2
  echo "$ldd_output" >&2
  exit 1
fi

# Package the binary
cd "$BUILD_DIR"
OUTPUT_DIR="iperf3-${VERSION}-linux-x86_64-static"
mkdir -p "$OUTPUT_DIR"
cp iperf/src/iperf3 "$OUTPUT_DIR/iperf3"

# Copy license and add a small README
cp iperf/LICENSE "$OUTPUT_DIR/LICENSE"
cat > "$OUTPUT_DIR/README.md" <<EOF
# iperf3 ${VERSION} — static build for Linux x86_64

This is a statically-linked build of iperf3 compiled with musl libc.
It should run on most Linux x86_64 distributions without installing
additional libraries.

## Usage

\`\`\`bash
./iperf3 --version
\`\`\`
EOF

ARCHIVE="iperf3-${VERSION}-linux-x86_64-static.tar.gz"
tar -czf "$ARCHIVE" "$OUTPUT_DIR"

# Move the archive to the original working directory
mv "$ARCHIVE" "$(pwd)/.."

cd "$(pwd)/.."

echo "=== Built: $(pwd)/${ARCHIVE} ==="
ls -lh "$ARCHIVE"
