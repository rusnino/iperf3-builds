#!/usr/bin/env bash
set -euo pipefail

# Build a statically-linked iperf3 binary using musl libc.
#
# Supported ARCH values:
#   x86_64, x86 (i686), aarch64, arm, armhf, armv7,
#   mips, mipsel, mips64, mips64el,
#   powerpc, ppc64le, s390x, riscv64, loongarch64
#
# Usage:
#   IPERF_VERSION=3.17.1 ./build-static.sh
#   ARCH=aarch64 IPERF_VERSION=3.17.1 ./build-static.sh
#
# Build with OpenSSL (RSA auth support):
#   AUTH=true IPERF_VERSION=3.17.1 ./build-static.sh
#   AUTH=true ARCH=aarch64 IPERF_VERSION=3.17.1 ./build-static.sh

IPERF_VERSION="${IPERF_VERSION:-}"
if [[ -z "$IPERF_VERSION" ]]; then
  echo "ERROR: IPERF_VERSION is not set" >&2
  exit 1
fi

ARCH="${ARCH:-x86_64}"
AUTH="${AUTH:-}"
AUTH_SUFFIX=""
if [ "$AUTH" = "true" ]; then
  AUTH_SUFFIX="-auth"
fi

# Upstream iperf tags do not have a 'v' prefix (e.g. 3.22, 3.16-beta1).
VERSION="$IPERF_VERSION"

echo "=== Building static iperf3 ${VERSION} for ${ARCH}${AUTH_SUFFIX} ==="

# Save the repository root so we can place the final archive there.
REPO_ROOT="$(pwd)"

# Install build dependencies. Use sudo when not running as root (typical in
# GitHub Actions runners).
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

NATIVE_ARCH=""
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "x86" ]; then
  NATIVE_ARCH=1
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "=== Installing dependencies via apt-get ==="
  packages="build-essential musl-tools curl git autoconf automake libtool file xz-utils"
  if [ -z "$NATIVE_ARCH" ]; then
    packages="$packages qemu-user-static"
  fi
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq $packages
elif command -v apk >/dev/null 2>&1; then
  echo "=== Installing dependencies via apk ==="
  apk add --no-cache build-base musl curl git autoconf automake libtool
  if [ -z "$NATIVE_ARCH" ]; then
    apk add --no-cache qemu-user-static
  fi
else
  echo "ERROR: No supported package manager found" >&2
  exit 1
fi

# Select toolchain and configure host for cross builds.
CROSS_BASE="${REPO_ROOT}/cross-toolchain"
HOST=""
CC=""
QEMU_BIN=""
TARGET=""
case "$ARCH" in
  x86_64)
    TARGET="x86_64-linux-musl"
    CC="musl-gcc"
    ;;
  x86)
    TARGET="i686-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    ;;
  aarch64)
    TARGET="aarch64-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-aarch64-static"
    ;;
  arm)
    TARGET="arm-linux-musleabi"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-arm-static"
    ;;
  armhf)
    TARGET="armv6-linux-musleabihf"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-arm-static"
    ;;
  armv7)
    TARGET="armv7l-linux-musleabihf"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-arm-static"
    ;;
  mips)
    TARGET="mips-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-mips-static"
    ;;
  mipsel)
    TARGET="mipsel-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-mipsel-static"
    ;;
  mips64)
    TARGET="mips64-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-mips64-static"
    ;;
  mips64el)
    TARGET="mips64el-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-mips64el-static"
    ;;
  powerpc)
    TARGET="powerpc-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-ppc-static"
    ;;
  ppc64le)
    TARGET="powerpc64le-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-ppc64le-static"
    ;;
  s390x)
    TARGET="s390x-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-s390x-static"
    ;;
  riscv64)
    TARGET="riscv64-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-riscv64-static"
    ;;
  loongarch64)
    TARGET="loongarch64-linux-musl"
    HOST="$TARGET"
    CC="${CROSS_BASE}/${TARGET}/bin/${TARGET}-gcc"
    QEMU_BIN="qemu-loongarch64-static"
    ;;
  *)
    echo "ERROR: unsupported ARCH: ${ARCH}" >&2
    exit 1
    ;;
esac

if [ -n "$HOST" ]; then
  echo "=== Downloading musl cross toolchain for ${ARCH} ==="
  MUSL_CROSS_VERSION="${MUSL_CROSS_VERSION:-2642}"
  toolchain_filename="x86_64-${HOST}.tar.xz"
  toolchain_url="https://github.com/userdocs/qbt-musl-cross-make/releases/download/${MUSL_CROSS_VERSION}/${toolchain_filename}"
  rm -rf "$CROSS_BASE"
  mkdir -p "$CROSS_BASE"
  curl -fsSL --retry 5 --retry-delay 10 -o "/tmp/${toolchain_filename}" "$toolchain_url"
  tar -xJf "/tmp/${toolchain_filename}" -C "$CROSS_BASE"
  if [ ! -x "$CC" ]; then
    echo "ERROR: cross compiler not found at ${CC}" >&2
    exit 1
  fi
fi

# Clean up any previous build
BUILD_DIR="${REPO_ROOT}/iperf3-build-static-${ARCH}${AUTH_SUFFIX}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

TARBALL="iperf-${VERSION}.tar.gz"
URL="https://github.com/esnet/iperf/releases/download/${VERSION}/${TARBALL}"
SRC_DIR="iperf-${VERSION}"

if curl -fsSL --retry 5 --retry-delay 10 -o "$TARBALL" "$URL"; then
  echo "=== Extracting ${TARBALL} ==="
  tar -xzf "$TARBALL"
else
  echo "=== Tarball not available; cloning from Git tag ${VERSION} ==="
  git clone --branch "${VERSION}" --depth 1 https://github.com/esnet/iperf.git "${SRC_DIR}"
  cd "${SRC_DIR}"
  echo "=== Bootstrapping autotools ==="
  autoreconf -fi
  cd "$BUILD_DIR"
fi

OPENSSL_DIR=""
if [ "$AUTH" = "true" ]; then
  echo "=== Downloading static OpenSSL for ${TARGET} ==="
  OPENSSL_URL="https://github.com/userdocs/openssl/releases/latest/download/${TARGET}.tar.xz"
  rm -f openssl-static.tar.xz
  curl -fsSL --retry 5 --retry-delay 10 -o openssl-static.tar.xz "$OPENSSL_URL"
  mkdir -p openssl-static
  tar -xJf openssl-static.tar.xz -C openssl-static
  OPENSSL_DIR="$(pwd)/openssl-static"
fi

cd "${SRC_DIR}"

echo "=== Configuring static build ==="
# GCC 14+/16 treats some older iperf3 callback signatures as incompatible
# pointer types. Demote that specific diagnostic to a warning so legacy
# versions still build cleanly.
CFLAGS="-static -Wno-error=incompatible-pointer-types"

configure_flags=(--disable-shared --enable-static-bin)
if [ -n "${OPENSSL_DIR:-}" ]; then
  configure_flags+=(--with-openssl="$OPENSSL_DIR")
else
  configure_flags+=(--without-openssl)
fi

if [ -n "$HOST" ]; then
  ./configure CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="-static" --host="$HOST" "${configure_flags[@]}"
else
  ./configure CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="-static" "${configure_flags[@]}"
fi

echo "=== Building ==="
make -j"$(nproc)"

echo "=== Verifying static linkage ==="
if [ ! -f src/iperf3 ]; then
  echo "ERROR: iperf3 binary not found" >&2
  exit 1
fi

file_info=$(file src/iperf3)
echo "$file_info"

if readelf -d src/iperf3 2>/dev/null | grep -q 'NEEDED'; then
  echo "ERROR: binary is not statically linked" >&2
  exit 1
fi
echo "OK: binary is statically linked"

# Package the binary
cd "$BUILD_DIR"
OUTPUT_DIR="iperf3-${VERSION}-linux-${ARCH}-static${AUTH_SUFFIX}"
mkdir -p "$OUTPUT_DIR"
cp "${SRC_DIR}/src/iperf3" "$OUTPUT_DIR/iperf3"

# Copy license and add a small README
cp "${SRC_DIR}/LICENSE" "$OUTPUT_DIR/LICENSE"

if [ "$AUTH" = "true" ]; then
  auth_note="These builds include statically-linked OpenSSL, so iperf3's RSA authentication feature is available."
else
  auth_note="These builds do not include OpenSSL, so iperf3's RSA authentication feature is not available."
fi

cat > "$OUTPUT_DIR/README.md" <<EOF
# iperf3 ${VERSION} — static build for Linux ${ARCH}${AUTH_SUFFIX}

This is a statically-linked build of iperf3 compiled with musl libc.
It should run on most Linux ${ARCH} distributions without installing
additional libraries.

${auth_note}

## Usage

\`\`\`bash
./iperf3 --version
\`\`\`
EOF

ARCHIVE="iperf3-${VERSION}-linux-${ARCH}-static${AUTH_SUFFIX}.tar.gz"
tar -czf "$ARCHIVE" "$OUTPUT_DIR"
cp "$ARCHIVE" "$REPO_ROOT/"

echo "=== Smoke test ==="
cd "$REPO_ROOT"
tar -xzf "$ARCHIVE"
if [ -n "$NATIVE_ARCH" ]; then
  "${OUTPUT_DIR}/iperf3" --version
else
  if [ -z "${QEMU_BIN:-}" ]; then
    echo "ERROR: QEMU binary not configured for ${ARCH}" >&2
    exit 1
  fi
  "$QEMU_BIN" "${OUTPUT_DIR}/iperf3" --version
fi

echo "=== Built: ${REPO_ROOT}/${ARCHIVE} ==="
ls -lh "$ARCHIVE"
