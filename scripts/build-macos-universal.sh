#!/usr/bin/env bash
set -euo pipefail

# Package separate x86_64 and arm64 macOS iperf3 binaries into a universal2
# tarball.
# Usage: IPERF_VERSION=3.22 ./build-macos-universal.sh
# Expects macos-build-x86_64/iperf3 and macos-build-arm64/iperf3 in the
# current working directory.
#
# Build with OpenSSL (RSA auth support):
#   AUTH=true IPERF_VERSION=3.22 ./build-macos-universal.sh

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

VERSION="$IPERF_VERSION"

echo "=== Packaging universal2 iperf3 ${VERSION}${AUTH_SUFFIX} ==="

X86_DIR="macos-build-x86_64${AUTH_SUFFIX}"
ARM_DIR="macos-build-arm64${AUTH_SUFFIX}"

if [ ! -f "${X86_DIR}/iperf3" ]; then
  echo "ERROR: ${X86_DIR}/iperf3 not found" >&2
  exit 1
fi

if [ ! -f "${ARM_DIR}/iperf3" ]; then
  echo "ERROR: ${ARM_DIR}/iperf3 not found" >&2
  exit 1
fi

if [ ! -f "${X86_DIR}/LICENSE" ] && [ ! -f "${ARM_DIR}/LICENSE" ]; then
  echo "ERROR: LICENSE not found in ${X86_DIR} or ${ARM_DIR} directories" >&2
  exit 1
fi

# Ensure downloaded binaries are executable before lipo merges them.
chmod +x "${X86_DIR}/iperf3" "${ARM_DIR}/iperf3"

lipo -create "${X86_DIR}/iperf3" "${ARM_DIR}/iperf3" -output iperf3
codesign -s - iperf3
chmod +x iperf3

OUTPUT_DIR="iperf3-${VERSION}-macos-universal2${AUTH_SUFFIX}"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mv iperf3 "${OUTPUT_DIR}/iperf3"

if [ -f "${X86_DIR}/LICENSE" ]; then
  cp "${X86_DIR}/LICENSE" "${OUTPUT_DIR}/LICENSE"
else
  cp "${ARM_DIR}/LICENSE" "${OUTPUT_DIR}/LICENSE"
fi

if [ "$AUTH" = "true" ]; then
  auth_note="This build includes statically-linked OpenSSL, so iperf3's RSA authentication feature is available."
else
  auth_note="These builds do not include OpenSSL, so iperf3's RSA authentication feature is not available."
fi

cat > "${OUTPUT_DIR}/README.md" <<EOF
# iperf3 ${VERSION} — macOS universal2 build${AUTH_SUFFIX}

This is a universal2 (fat) binary of iperf3 that runs natively on both
Intel (x86_64) and Apple Silicon (arm64) Macs.

${auth_note}

Requirements: macOS 11.0 (Big Sur) or newer.

## Quarantine note

If you downloaded this archive through a web browser, macOS may mark the
binary with a quarantine flag and show a "developer cannot be verified"
warning when you first run it from Terminal. You can remove the flag with:

\`\`\`bash
xattr -d com.apple.quarantine iperf3
\`\`\`

Alternatively, open System Settings → Privacy & Security → "Allow anyway"
after the first launch attempt.

## Usage

\`\`\`bash
./iperf3 --version
\`\`\`
EOF

ARCHIVE="iperf3-${VERSION}-macos-universal2${AUTH_SUFFIX}.tar.gz"
tar -czf "$ARCHIVE" "$OUTPUT_DIR"

echo "=== Verifying universal2 binary ==="
lipo -info "${OUTPUT_DIR}/iperf3"
file_info=$(file "${OUTPUT_DIR}/iperf3")
echo "$file_info"

if ! echo "$file_info" | grep -q "universal binary"; then
  echo "ERROR: output is not a universal binary" >&2
  exit 1
fi

echo "=== Smoke test ==="
"${OUTPUT_DIR}/iperf3" --version

echo "=== Built: $(pwd)/${ARCHIVE} ==="
ls -lh "$ARCHIVE"
