#!/usr/bin/env bash
set -euo pipefail

# Build a single-architecture iperf3 binary on macOS.
# Usage:
#   IPERF_VERSION=3.22 ARCH=x86_64 ./build-macos-arch.sh
#   IPERF_VERSION=3.22 ARCH=arm64  ./build-macos-arch.sh
#
# Build with OpenSSL (RSA auth support):
#   AUTH=true IPERF_VERSION=3.22 ARCH=x86_64 ./build-macos-arch.sh

IPERF_VERSION="${IPERF_VERSION:-}"
if [[ -z "$IPERF_VERSION" ]]; then
  echo "ERROR: IPERF_VERSION is not set" >&2
  exit 1
fi

ARCH="${ARCH:-}"
if [[ -z "$ARCH" ]]; then
  echo "ERROR: ARCH is not set (expected x86_64 or arm64)" >&2
  exit 1
fi
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
  echo "ERROR: unsupported ARCH: ${ARCH}" >&2
  exit 1
fi

AUTH="${AUTH:-}"
AUTH_SUFFIX=""
if [ "$AUTH" = "true" ]; then
  AUTH_SUFFIX="-auth"
fi

VERSION="$IPERF_VERSION"

echo "=== Building macOS iperf3 ${VERSION} for ${ARCH}${AUTH_SUFFIX} ==="

REPO_ROOT="$(pwd)"

BUILD_DIR="${REPO_ROOT}/iperf3-build-macos-${ARCH}${AUTH_SUFFIX}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

OPENSSL_DIR=""
if [ "$AUTH" = "true" ]; then
  echo "=== Installing OpenSSL via Homebrew ==="
  brew install openssl@3

  echo "=== Preparing static OpenSSL libraries ==="
  OPENSSL_BREW_PREFIX="$(brew --prefix openssl@3)"
  mkdir -p openssl_libs/include openssl_libs/lib
  cp -r "${OPENSSL_BREW_PREFIX}/include/openssl" openssl_libs/include/
  cp "${OPENSSL_BREW_PREFIX}/lib/libcrypto.a" openssl_libs/lib/
  cp "${OPENSSL_BREW_PREFIX}/lib/libssl.a" openssl_libs/lib/
  OPENSSL_DIR="$(pwd)/openssl_libs"
fi

TARBALL="iperf-${VERSION}.tar.gz"
URL="https://github.com/esnet/iperf/releases/download/${VERSION}/${TARBALL}"
SRC_DIR="iperf-${VERSION}"

if curl -fsSL -o "$TARBALL" "$URL"; then
  echo "=== Extracting ${TARBALL} ==="
  tar -xzf "$TARBALL"
else
  echo "=== Tarball not available; cloning from Git tag ${VERSION} ==="
  echo "=== Installing autotools via Homebrew ==="
  brew install autoconf automake libtool
  git clone --branch "${VERSION}" --depth 1 https://github.com/esnet/iperf.git "${SRC_DIR}"
  cd "${SRC_DIR}"
  echo "=== Bootstrapping autotools ==="
  autoreconf -fi
  cd "$BUILD_DIR"
fi

cd "${SRC_DIR}"

export MACOSX_DEPLOYMENT_TARGET=11.0

configure_flags=(--disable-shared)
if [ -n "${OPENSSL_DIR:-}" ]; then
  configure_flags+=(--with-openssl="$OPENSSL_DIR")
  export LDFLAGS="${LDFLAGS:-} -L${OPENSSL_DIR}/lib -framework CoreFoundation -framework Security"
else
  configure_flags+=(--without-openssl)
fi

echo "=== Configuring macOS ${ARCH} build ==="
./configure "${configure_flags[@]}"

echo "=== Building ==="
make -j"$(sysctl -n hw.ncpu)"

echo "=== Verifying architecture ==="
file_info=$(file src/iperf3)
echo "$file_info"

if [[ "$ARCH" == "x86_64" && ! "$file_info" =~ x86_64 ]]; then
  echo "ERROR: binary is not x86_64" >&2
  exit 1
fi

if [[ "$ARCH" == "arm64" && ! "$file_info" =~ arm64 ]]; then
  echo "ERROR: binary is not arm64" >&2
  exit 1
fi

echo "=== Smoke test ==="
"${BUILD_DIR}/${SRC_DIR}/src/iperf3" --version

OUTPUT_DIR="macos-build-${ARCH}${AUTH_SUFFIX}"
mkdir -p "${REPO_ROOT}/${OUTPUT_DIR}"
cp "src/iperf3" "${REPO_ROOT}/${OUTPUT_DIR}/iperf3"
cp "LICENSE" "${REPO_ROOT}/${OUTPUT_DIR}/LICENSE"

echo "=== Built: ${REPO_ROOT}/${OUTPUT_DIR}/iperf3 ==="
file "${REPO_ROOT}/${OUTPUT_DIR}/iperf3"
