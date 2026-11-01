#!/usr/bin/env bash
set -euo pipefail

# Build a statically-linked iperf3 binary using zig cc and musl libc.
#
# Supported ARCH values are defined in targets.json.
#
# Usage:
#   IPERF_VERSION=3.22 ./scripts/build-static.sh
#   ARCH=aarch64 IPERF_VERSION=3.22 ./scripts/build-static.sh
#   AUTH=true ARCH=aarch64 IPERF_VERSION=3.22 ./scripts/build-static.sh

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

VERSION="$IPERF_VERSION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$REPO_ROOT/targets.json"

if [ ! -f "$CATALOG" ]; then
  echo "ERROR: targets catalog not found: $CATALOG" >&2
  exit 1
fi

# Read target metadata from the catalog.
python3 - "$CATALOG" "$ARCH" <<'PY' >/dev/null
import sys, json
catalog, arch = sys.argv[1], sys.argv[2]
data = json.load(open(catalog))
if arch not in data['arch']:
    print(f"ERROR: unsupported ARCH: {arch}", file=sys.stderr)
    sys.exit(1)
PY

ZIG_TARGET=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['zig_target'])")
OPENSSL_TARGET=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['openssl_target'])")
QEMU_BIN=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['qemu'] or '')")

if [ "$AUTH" = "true" ]; then
  CATALOG_AUTH=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['auth'])")
  if [ "$CATALOG_AUTH" != "True" ]; then
    echo "ERROR: auth is not supported for ARCH=$ARCH according to $CATALOG" >&2
    exit 1
  fi
fi

echo "=== Building static iperf3 ${VERSION} for ${ARCH}${AUTH_SUFFIX} (zig target: ${ZIG_TARGET}) ==="

# Determine whether this is a native x86 build that can run without QEMU.
NATIVE_ARCH=""
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "x86" ]; then
  NATIVE_ARCH=1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "=== Installing dependencies via apt-get ==="
  packages="build-essential curl git autoconf automake libtool file xz-utils python3"
  if [ -z "$NATIVE_ARCH" ]; then
    packages="$packages qemu-user-static"
  fi
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq $packages
elif command -v apk >/dev/null 2>&1; then
  echo "=== Installing dependencies via apk ==="
  packages="build-base curl git autoconf automake libtool file xz-utils python3"
  if [ -z "$NATIVE_ARCH" ]; then
    packages="$packages qemu-user-static"
  fi
  apk add --no-cache $packages
else
  echo "ERROR: No supported package manager found" >&2
  exit 1
fi

# Install the official Zig toolchain.
ZIG_VERSION="${ZIG_VERSION:-0.17.0}"
ZIG_DIR="${ZIG_DIR:-$REPO_ROOT/.zig}"
ZIG_BIN="$ZIG_DIR/zig"

if [ ! -x "$ZIG_BIN" ]; then
  echo "=== Installing Zig ${ZIG_VERSION} ==="
  rm -rf "$ZIG_DIR"
  mkdir -p "$ZIG_DIR"
  host_arch="$(uname -m)"
  host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"

  case "${host_arch}-${host_os}" in
    x86_64-linux) zig_tuple="x86_64-linux" ;;
    aarch64-linux) zig_tuple="aarch64-linux" ;;
    *) echo "ERROR: unsupported host for Zig install: ${host_arch}-${host_os}" >&2; exit 1 ;;
  esac

  # Fetch the official Zig download index. This is the canonical source for
  # tarball URLs and checksums after the Zig source repository migrated to
  # Codeberg; binary releases remain distributed via ziglang.org and its
  # community mirrors.
  index_url="https://ziglang.org/download/index.json"
  index_file="/tmp/zig-index-${ZIG_VERSION}.json"
  curl -fsSL --retry 5 --retry-delay 10 -o "$index_file" "$index_url"

  zig_metadata=$(python3 - "$index_file" "$ZIG_VERSION" "$zig_tuple" <<'PY'
import sys, json
index_file, version, host = sys.argv[1:]
data = json.load(open(index_file))
if version not in data:
    print(f"ERROR: Zig version {version} not in download index", file=sys.stderr)
    sys.exit(1)
if host not in data[version]:
    print(f"ERROR: host {host} not in Zig {version} download index", file=sys.stderr)
    sys.exit(1)
meta = data[version][host]
print(meta["tarball"])
print(meta["shasum"])
PY
)

  url=$(echo "$zig_metadata" | sed -n '1p')
  expected_sha=$(echo "$zig_metadata" | sed -n '2p')

  zig_basename="zig-${zig_tuple}-${ZIG_VERSION}"
  tarball="${zig_basename}.tar.xz"
  tarball_path="/tmp/${tarball}"

  echo "Downloading Zig from: $url"
  curl -fsSL --retry 5 --retry-delay 10 -o "$tarball_path" "$url"

  echo "Verifying Zig tarball SHA-256"
  echo "$expected_sha  $tarball_path" | sha256sum -c -

  tar -xJf "$tarball_path" -C "$ZIG_DIR" --strip-components=1
fi

export PATH="$ZIG_DIR:$PATH"

# Create wrapper scripts so that autotools and OpenSSL see plain cc/ar/ranlib.
WRAPPER_DIR="$(mktemp -d)"
trap 'rm -rf "$WRAPPER_DIR"' EXIT

cat > "$WRAPPER_DIR/cc" <<EOF
#!/usr/bin/env bash
exec "$ZIG_BIN" cc -target "$ZIG_TARGET" "\$@"
EOF
chmod +x "$WRAPPER_DIR/cc"

cat > "$WRAPPER_DIR/c++" <<EOF
#!/usr/bin/env bash
exec "$ZIG_BIN" c++ -target "$ZIG_TARGET" "\$@"
EOF
chmod +x "$WRAPPER_DIR/c++"

cat > "$WRAPPER_DIR/ar" <<EOF
#!/usr/bin/env bash
exec "$ZIG_BIN" ar "\$@"
EOF
chmod +x "$WRAPPER_DIR/ar"

cat > "$WRAPPER_DIR/ranlib" <<EOF
#!/usr/bin/env bash
exec "$ZIG_BIN" ranlib "\$@"
EOF
chmod +x "$WRAPPER_DIR/ranlib"

export PATH="$WRAPPER_DIR:$PATH"
export CC="$WRAPPER_DIR/cc"
export CXX="$WRAPPER_DIR/c++"
export AR="$WRAPPER_DIR/ar"
export RANLIB="$WRAPPER_DIR/ranlib"

# Clean up any previous build.
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

OPENSSL_PREFIX=""
if [ "$AUTH" = "true" ]; then
  echo "=== Building OpenSSL from source for ${ARCH} ==="
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.5}"
  openssl_tarball="openssl-${OPENSSL_VERSION}.tar.gz"
  openssl_url="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${openssl_tarball}"
  rm -f "$openssl_tarball"
  curl -fsSL --retry 5 --retry-delay 10 -o "$openssl_tarball" "$openssl_url"
  tar -xzf "$openssl_tarball"
  cd "openssl-${OPENSSL_VERSION}"

  OPENSSL_PREFIX="$(pwd)/../openssl-prefix"
  rm -rf "$OPENSSL_PREFIX"
  mkdir -p "$OPENSSL_PREFIX"

  ./Configure \
    "$OPENSSL_TARGET" \
    --prefix="$OPENSSL_PREFIX" \
    --openssldir="$OPENSSL_PREFIX/ssl" \
    no-shared \
    no-zlib \
    -static \
    -DOPENSSL_NO_AFALGENG \
    threads

  make -j"$(nproc)" build_libs
  make install_sw

  # iperf3's configure looks in $prefix/lib; OpenSSL may install to lib64.
  if [ -d "${OPENSSL_PREFIX}/lib64" ] && [ ! -d "${OPENSSL_PREFIX}/lib" ]; then
    ln -s lib64 "${OPENSSL_PREFIX}/lib"
  fi

  cd "$BUILD_DIR"
fi

cd "${SRC_DIR}"

echo "=== Configuring static build ==="
# Demote incompatible-pointer-types to a warning so older iperf3 versions still build.
CFLAGS="-static -Wno-error=incompatible-pointer-types"

configure_flags=(--disable-shared --enable-static-bin)
if [ -n "$OPENSSL_PREFIX" ]; then
  configure_flags+=(--with-openssl="$OPENSSL_PREFIX")
else
  configure_flags+=(--without-openssl)
fi

./configure \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="-static" \
  --host="$ZIG_TARGET" \
  "${configure_flags[@]}"

echo "=== Building ==="
make -j"$(nproc)"

echo "=== Verifying binary ==="
if [ ! -f src/iperf3 ]; then
  echo "ERROR: iperf3 binary not found" >&2
  exit 1
fi

file src/iperf3
"$REPO_ROOT/scripts/verify-elf.sh" src/iperf3 "$ARCH"

if [ "$AUTH" = "true" ]; then
  echo "=== Verifying authentication feature ==="
  if ! src/iperf3 --version 2>/dev/null | grep -q 'authentication'; then
    echo "ERROR: auth binary does not report authentication support" >&2
    exit 1
  fi
  echo "OK: authentication feature present"
fi

# Package the binary.
cd "$BUILD_DIR"
OUTPUT_DIR="iperf3-${VERSION}-linux-${ARCH}-static${AUTH_SUFFIX}"
mkdir -p "$OUTPUT_DIR"
cp "${SRC_DIR}/src/iperf3" "$OUTPUT_DIR/iperf3"
cp "${SRC_DIR}/LICENSE" "$OUTPUT_DIR/LICENSE"

if [ "$AUTH" = "true" ]; then
  auth_note="These builds include statically-linked OpenSSL, so iperf3's RSA authentication feature is available."
else
  auth_note="These builds do not include OpenSSL, so iperf3's RSA authentication feature is not available."
fi

# Include a manifest with provenance and compatibility metadata.
MANIFEST="$OUTPUT_DIR/MANIFEST.json"
python3 - "$CATALOG" "$ARCH" "$VERSION" "$ZIG_VERSION" "$AUTH" "$auth_note" <<'PY' > "$MANIFEST"
import sys, json

catalog_path, arch, iperf_version, zig_version, auth, auth_note = sys.argv[1:7]
data = json.load(open(catalog_path))
meta = data['arch'][arch]
manifest = {
    'iperf_version': iperf_version,
    'target_name': arch,
    'zig_target': meta['zig_target'],
    'zig_version': zig_version,
    'openssl_version': '3.6.5' if auth == 'true' else None,
    'cpu_baseline': meta.get('cpu'),
    'abi': meta.get('abi'),
    'endianness': meta.get('endianness'),
    'auth': auth == 'true',
    'auth_note': auth_note,
    'libc': 'musl (via zig cc)',
    'build_type': 'static',
}
print(json.dumps(manifest, indent=2))
PY

cat > "$OUTPUT_DIR/README.md" <<EOF
# iperf3 ${VERSION} — static build for Linux ${ARCH}${AUTH_SUFFIX}

This is a statically-linked build of iperf3 compiled with zig cc and musl libc.
It should run on most Linux ${ARCH} distributions without installing
additional libraries.

${auth_note}

See MANIFEST.json for provenance and compatibility metadata.

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
