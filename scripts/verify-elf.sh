#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <binary> <arch>" >&2
  exit 1
fi

BINARY="$1"
ARCH="$2"

if [ ! -f "$BINARY" ]; then
  echo "ERROR: binary not found: $BINARY" >&2
  exit 1
fi

CATALOG="$(dirname "$0")/../targets.json"

expected_class=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['elf_class'])")
expected_data=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['elf_data'])")
expected_machine=$(python3 -c "import json; print(json.load(open('$CATALOG'))['arch']['$ARCH']['elf_machine'])")

echo "=== ELF header verification for $ARCH ==="
header=$(readelf -h "$BINARY")

actual_class=$(echo "$header" | awk '/^[[:space:]]*Class:/{sub(/^[[:space:]]*Class:[[:space:]]*/, ""); print; exit}')
actual_data=$(echo "$header" | awk '/^[[:space:]]*Data:/{sub(/^[[:space:]]*Data:[[:space:]]*/, ""); print; exit}')
actual_machine=$(echo "$header" | awk '/^[[:space:]]*Machine:/{sub(/^[[:space:]]*Machine:[[:space:]]*/, ""); print; exit}')

echo "Class:    $actual_class (expected $expected_class)"
echo "Data:     $actual_data (expected $expected_data)"
echo "Machine:  $actual_machine (expected $expected_machine)"

if [ "$actual_class" != "$expected_class" ]; then
  echo "ERROR: ELF class mismatch for $ARCH" >&2
  exit 1
fi

if [ "$actual_data" != "$expected_data" ]; then
  echo "ERROR: ELF data/endianness mismatch for $ARCH" >&2
  exit 1
fi

if [ "$actual_machine" != "$expected_machine" ]; then
  echo "ERROR: ELF machine mismatch for $ARCH" >&2
  exit 1
fi

echo "=== Dynamic section check ==="
if readelf -d "$BINARY" 2>/dev/null | grep -q 'NEEDED'; then
  echo "ERROR: binary has dynamic dependencies" >&2
  exit 1
fi

echo "=== Interpreter check ==="
if readelf -l "$BINARY" 2>/dev/null | grep -q 'INTERP'; then
  echo "ERROR: binary has a program interpreter (not statically linked)" >&2
  exit 1
fi

echo "OK: $BINARY is a statically linked $ARCH ELF binary"
