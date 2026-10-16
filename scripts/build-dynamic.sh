#!/usr/bin/env bash
set -euo pipefail

# Build a dynamically-linked iperf3 binary using glibc.
# Intended to run in an AlmaLinux 8 / CentOS Stream 8 compatible container so
# the resulting binary works on glibc 2.28 targets (e.g. Cisco IOS-XE guestshell).
# Usage: IPERF_VERSION=3.17.1 ./build-dynamic.sh
#
# Build with OpenSSL (RSA auth support):
#   AUTH=true IPERF_VERSION=3.17.1 ./build-dynamic.sh
#
# The auth variant statically links OpenSSL into the iperf3 binary while
# keeping glibc dynamically linked, so no runtime OpenSSL libraries are needed.

IPERF_VERSION="${IPERF_VERSION:-}"
if [[ -z "$IPERF_VERSION" ]]; then
  echo "ERROR: IPERF_VERSION is not set" >&2
  exit 1
fi

AUTH="${AUTH:-}"
AUTH_SUFFIX=""
if [ "$AUTH" = "true" ]; then
  AUTH_SUFFIX="-auth"
fi

# Upstream iperf tags do not have a 'v' prefix (e.g. 3.22, 3.16-beta1).
VERSION="$IPERF_VERSION"

echo "=== Building dynamic iperf3 ${VERSION}${AUTH_SUFFIX} ==="

# Install build dependencies
if command -v apt-get >/dev/null 2>&1; then
  echo "=== Installing dependencies via apt-get ==="
  apt-get update -qq
  apt-get install -y -qq build-essential curl git autoconf automake libtool
  if [ "$AUTH" = "true" ]; then
    apt-get install -y -qq libssl-dev zlib1g-dev libzstd-dev
  fi
elif command -v yum >/dev/null 2>&1; then
  echo "=== Installing dependencies via yum ==="
  yum install -y gcc make curl git autoconf automake libtool
  if [ "$AUTH" = "true" ]; then
    yum install -y openssl-devel openssl-static zlib-static zstd-static
  fi
elif command -v apk >/dev/null 2>&1; then
  echo "=== Installing dependencies via apk ==="
  apk add --no-cache build-base curl git autoconf automake libtool
  if [ "$AUTH" = "true" ]; then
    apk add --no-cache openssl-dev openssl-libs-static zlib-static zstd-static
  fi
else
  echo "ERROR: No supported package manager found" >&2
  exit 1
fi

# Clean up any previous build
BUILD_DIR="$(pwd)/iperf3-build-dynamic${AUTH_SUFFIX}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

OPENSSL_DIR=""
if [ "$AUTH" = "true" ]; then
  echo "=== Preparing static OpenSSL libraries ==="
  mkdir -p openssl-static-local/include openssl-static-local/lib

  # Copy headers
  if [ -d /usr/include/openssl ]; then
    cp -r /usr/include/openssl openssl-static-local/include/
  elif [ -d /usr/local/include/openssl ]; then
    cp -r /usr/local/include/openssl openssl-static-local/include/
  else
    echo "ERROR: OpenSSL headers not found" >&2
    exit 1
  fi

  # Find and copy static libraries
  for lib in libcrypto.a libssl.a; do
    found=$(find /usr/lib /usr/lib64 /lib /usr/local/lib -name "$lib" 2>/dev/null | head -1)
    if [ -z "${found:-}" ]; then
      echo "ERROR: static OpenSSL library ${lib} not found" >&2
      exit 1
    fi
    cp "$found" openssl-static-local/lib/
  done

  # Also copy static dependency libraries so the final binary does not need
  # zlib/libzstd at runtime.
  for lib in libz.a libzstd.a; do
    found=$(find /usr/lib /usr/lib64 /lib /usr/local/lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "${found:-}" ]; then
      cp "$found" openssl-static-local/lib/
    fi
  done

  OPENSSL_DIR="$(pwd)/openssl-static-local"
fi

TARBALL="iperf-${VERSION}.tar.gz"
URL="https://github.com/esnet/iperf/releases/download/${VERSION}/${TARBALL}"
SRC_DIR="iperf-${VERSION}"

if curl -fsSL -o "$TARBALL" "$URL"; then
  echo "=== Extracting ${TARBALL} ==="
  tar -xzf "$TARBALL"
else
  echo "=== Tarball not available; cloning from Git tag ${VERSION} ==="

  # Upstream tags that lack release tarballs may require a newer autoconf than
  # AlmaLinux 8 / CentOS Stream 8 ship. Build a recent autoconf from source.
  AUTOCONF_VERSION=2.71
  echo "=== Building autoconf ${AUTOCONF_VERSION} from source ==="
  curl -fsSL "https://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.gz" | tar -xz
  cd "autoconf-${AUTOCONF_VERSION}"
  ./configure --prefix=/usr/local
  make -j"$(nproc)"
  make install
  export PATH=/usr/local/bin:$PATH
  cd "$BUILD_DIR"

  git clone --branch "${VERSION}" --depth 1 https://github.com/esnet/iperf.git "${SRC_DIR}"
  cd "${SRC_DIR}"
  echo "=== Bootstrapping autotools ==="
  autoreconf -fi
  cd "$BUILD_DIR"
fi

cd "${SRC_DIR}"

echo "=== Configuring dynamic build ==="
# Build the iperf3 binary without the internal shared library so the
# resulting executable only depends on system glibc.
configure_flags=(--disable-shared)

if [ -n "${OPENSSL_DIR:-}" ]; then
  configure_flags+=(--with-openssl="$OPENSSL_DIR")
  export PKG_CONFIG_PATH=""
  export CPPFLAGS="${CPPFLAGS:-} -I${OPENSSL_DIR}/include"
  export LDFLAGS="${LDFLAGS:-} -L${OPENSSL_DIR}/lib"
  export LIBS="${LIBS:-} -ldl -lpthread -lz -lzstd"
fi

./configure "${configure_flags[@]}"

echo "=== Building ==="
make -j"$(nproc)"

# Package the binary
cd "$BUILD_DIR"
OUTPUT_DIR="iperf3-${VERSION}-linux-x86_64-dynamic${AUTH_SUFFIX}"
mkdir -p "$OUTPUT_DIR"
# With --disable-shared --enable-static-bin the real binary is produced at src/iperf3.
cp "${SRC_DIR}/src/iperf3" "$OUTPUT_DIR/iperf3"

# Copy license and add a small README
cp "${SRC_DIR}/LICENSE" "$OUTPUT_DIR/LICENSE"

if [ "$AUTH" = "true" ]; then
  auth_note="This build statically links OpenSSL, so iperf3's RSA authentication feature is available. The binary still depends on the system glibc."
else
  auth_note="These builds do not include OpenSSL, so iperf3's RSA authentication feature is not available."
fi

cat > "$OUTPUT_DIR/README.md" <<EOF
# iperf3 ${VERSION} — dynamic build for Linux x86_64${AUTH_SUFFIX}

This is a dynamically-linked build of iperf3 compiled with glibc on an
AlmaLinux 8 / CentOS Stream 8 compatible environment. It should run on
Linux x86_64 systems with glibc 2.28 or newer. For maximum portability,
use the static build instead.

${auth_note}

## Usage

\`\`\`bash
./iperf3 --version
\`\`\`
EOF

ARCHIVE="iperf3-${VERSION}-linux-x86_64-dynamic${AUTH_SUFFIX}.tar.gz"
tar -czf "$ARCHIVE" "$OUTPUT_DIR"

echo "=== Smoke test ==="
"${OUTPUT_DIR}/iperf3" --version

echo "=== Built: $(pwd)/${ARCHIVE} ==="
ls -lh "$ARCHIVE"
