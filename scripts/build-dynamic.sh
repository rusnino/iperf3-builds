#!/usr/bin/env bash
set -euo pipefail

# Build a dynamically-linked iperf3 binary using glibc.
# Intended to run in an AlmaLinux 8 / CentOS Stream 8 compatible container so
# the resulting binary works on glibc 2.28 targets (e.g. Cisco IOS-XE guestshell).
# Usage: IPERF_VERSION=3.17.1 ./build-dynamic.sh

IPERF_VERSION="${IPERF_VERSION:-}"
if [[ -z "$IPERF_VERSION" ]]; then
  echo "ERROR: IPERF_VERSION is not set" >&2
  exit 1
fi

# Upstream iperf tags do not have a 'v' prefix (e.g. 3.22, 3.16-beta1).
VERSION="$IPERF_VERSION"

echo "=== Building dynamic iperf3 ${VERSION} ==="

# Install build dependencies
if command -v apt-get >/dev/null 2>&1; then
  echo "=== Installing dependencies via apt-get ==="
  apt-get update -qq
  apt-get install -y -qq build-essential curl
elif command -v yum >/dev/null 2>&1; then
  echo "=== Installing dependencies via yum ==="
  yum install -y gcc make curl
elif command -v apk >/dev/null 2>&1; then
  echo "=== Installing dependencies via apk ==="
  apk add --no-cache build-base curl
else
  echo "ERROR: No supported package manager found" >&2
  exit 1
fi

# Clean up any previous build
BUILD_DIR="$(pwd)/iperf3-build-dynamic"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

TARBALL="iperf-${VERSION}.tar.gz"
URL="https://github.com/esnet/iperf/releases/download/${VERSION}/${TARBALL}"

echo "=== Downloading ${URL} ==="
curl -fsSL -o "$TARBALL" "$URL"

echo "=== Extracting ${TARBALL} ==="
tar -xzf "$TARBALL"
cd "iperf-${VERSION}"

echo "=== Configuring dynamic build ==="
# Build the iperf3 binary without the internal shared library so the
# resulting executable only depends on system glibc.
./configure --disable-shared

echo "=== Building ==="
make -j"$(nproc)"

# Package the binary
cd "$BUILD_DIR"
OUTPUT_DIR="iperf3-${VERSION}-linux-x86_64-dynamic"
mkdir -p "$OUTPUT_DIR"
# With --disable-shared the real binary is produced at src/iperf3.
cp "iperf-${VERSION}/src/iperf3" "$OUTPUT_DIR/iperf3"

# Copy license and add a small README
cp "iperf-${VERSION}/LICENSE" "$OUTPUT_DIR/LICENSE"
cat > "$OUTPUT_DIR/README.md" <<EOF
# iperf3 ${VERSION} — dynamic build for Linux x86_64

This is a dynamically-linked build of iperf3 compiled with glibc on an
AlmaLinux 8 / CentOS Stream 8 compatible environment. It should run on
Linux x86_64 systems with glibc 2.28 or newer. For maximum portability,
use the static build instead.

## Usage

\`\`\`bash
./iperf3 --version
\`\`\`
EOF

ARCHIVE="iperf3-${VERSION}-linux-x86_64-dynamic.tar.gz"
tar -czf "$ARCHIVE" "$OUTPUT_DIR"

echo "=== Built: $(pwd)/${ARCHIVE} ==="
ls -lh "$ARCHIVE"
