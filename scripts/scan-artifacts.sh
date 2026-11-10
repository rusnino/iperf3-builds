#!/usr/bin/env bash
# Scan release artifacts with VirusTotal and a secondary AV service.
#
# Usage:
#   VT_API_KEY=... METADEFENDER_API_KEY=... ./scripts/scan-artifacts.sh <artifacts-dir>
#
# Writes scan-report.json and scan-report.md into <artifacts-dir>/scan-reports/.
set -euo pipefail

ARTIFACTS_DIR="${1:-}"
if [ -z "$ARTIFACTS_DIR" ] || [ ! -d "$ARTIFACTS_DIR" ]; then
  echo "ERROR: usage: $0 <artifacts-directory>" >&2
  exit 1
fi

ARTIFACTS_DIR="$(cd "$ARTIFACTS_DIR" && pwd)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$REPO_ROOT/scripts/scan-virustotal.py"
REPORTS_DIR="$ARTIFACTS_DIR/scan-reports"
MANIFEST="$REPORTS_DIR/manifest.json"

mkdir -p "$REPORTS_DIR"

python3 - "$ARTIFACTS_DIR" "$MANIFEST" <<'PY'
import sys, json, hashlib, pathlib
artifacts_dir = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
manifest_path.parent.mkdir(parents=True, exist_ok=True)
entries = []
for path in sorted(artifacts_dir.glob('iperf3-*.tar.gz')):
    data = path.read_bytes()
    entries.append({
        'file': str(path),
        'basename': path.name,
        'sha256': hashlib.sha256(data).hexdigest(),
        'size': len(data),
    })
manifest_path.write_text(json.dumps(entries, indent=2) + '\n')
print(f'Collected {len(entries)} artifacts for scanning', file=sys.stderr)
PY

"$SCANNER" "$MANIFEST" "$REPORTS_DIR"

echo "Scan reports written to: $REPORTS_DIR"
ls -la "$REPORTS_DIR"/scan-report.*
