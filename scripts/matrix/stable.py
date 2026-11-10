#!/usr/bin/env python3
"""Emit the stable Linux static build matrix from targets.json.

Used by `.github/workflows/build-release.yml` (job `generate-linux-static-matrix`).
"""

import json
import pathlib
import sys


def main() -> int:
    catalog = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "targets.json")
    data = json.loads(catalog.read_text())

    matrix: dict = {"include": []}
    for arch, meta in data["arch"].items():
        if not meta.get("stable", False):
            continue
        matrix["include"].append({"arch": arch, "auth": False})
        if meta.get("auth", True):
            matrix["include"].append({"arch": arch, "auth": True})

    json.dump(matrix, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
