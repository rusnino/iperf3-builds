#!/usr/bin/env bash
# Smoke-test a built Linux iperf3 binary for one target in targets.json.
#
# Runs `iperf3 --version` natively for the build host architecture and under
# QEMU user-mode emulation for everything else. Fails when the emulator or the
# `qemu-<arch>` package is missing, so a release can never silently skip the
# smoke test.
#
# Usage:
#   ./scripts/smoke-test.sh <arch> <path-to-iperf3>
set -euo pipefail

ARCH="${1:-}"
BINARY="${2:-}"

if [ -z "$ARCH" ] || [ -z "$BINARY" ]; then
  echo "ERROR: usage: $0 <arch> <path-to-iperf3>" >&2
  exit 1
fi

if [ ! -f "$BINARY" ]; then
  echo "ERROR: binary not found: $BINARY" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Reads zig_target and qemu from targets.json and picks the best match against
# the current host machine. Prints "<host-match|qemu|native> <qemu-name>".
read -r MODE QEMU_NAME TARGET <<EOF
$(python3 - "$REPO_ROOT/targets.json" "$ARCH" "$(uname -m)" <<'PY'
import json
import sys

catalog, arch, host = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(catalog))["arch"]
if arch not in data:
    sys.exit(f"ERROR: unknown arch {arch!r} in targets.json")
meta = data[arch]
target = meta["zig_target"]
qemu = meta.get("qemu") or ""

# Map the build host (x86_64 GitHub runners) to the catalog architecture that
# produces binaries the host can execute directly.
host_alias = {"x86_64": "x86_64", "amd64": "x86_64"}.get(host, host)
host_target = data.get(host_alias, {}).get("zig_target")

if host_target == target:
    print("host-match", "-", target)
elif qemu:
    print("qemu", qemu, target)
else:
    print("native", "-", target)
PY
)
EOF

case "$MODE" in
  host-match)
    echo "Running native smoke test for $ARCH ($TARGET)"
    "$BINARY" --version
    ;;
  native)
    echo "Running native smoke test for $ARCH ($TARGET)"
    "$BINARY" --version
    ;;
  qemu)
    if ! command -v "$QEMU_NAME" >/dev/null 2>&1; then
      echo "ERROR: $QEMU_NAME not found; cannot smoke-test $ARCH ($TARGET)" >&2
      if command -v apt-get >/dev/null 2>&1; then
        echo "Install it with: sudo apt-get install -y binfmt-support qemu-user-static" >&2
      fi
      exit 1
    fi
    echo "Running QEMU smoke test for $ARCH ($TARGET) via $QEMU_NAME"
    "$QEMU_NAME" --version | head -n 1
    # -L is irrelevant for static musl binaries but harmless; QEMU needs the
    # binary to be executable.
    QEMU_LD_PREFIX=/ "$QEMU_NAME" "$BINARY" --version
    ;;
  *)
    echo "ERROR: cannot determine smoke-test mode for $ARCH (mode=$MODE)" >&2
    exit 1
    ;;
esac

echo "Smoke test passed for $ARCH"
