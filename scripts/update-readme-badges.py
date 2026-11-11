#!/usr/bin/env python3
"""Render the antivirus-scan status badges in README.md.

Reads the scan report attached to the latest (or given) GitHub release and
rewrites the block between the AV-BADGES markers. If no report is available the
block switches to a neutral "unavailable" state instead of showing stale
numbers.

Usage:
    scripts/update-readme-badges.py [--release 3.22] [--repo owner/name]
    GH_TOKEN=... scripts/update-readme-badges.py

Environment:
    GH_TOKEN   token used by `gh`/the API (defaults to gh's own credentials)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.parse
from pathlib import Path

BEGIN = "<!-- AV-BADGES:BEGIN -->"
END = "<!-- AV-BADGES:END -->"
README = Path(__file__).resolve().parent.parent / "README.md"
SCANNERS = ("virustotal", "metadefender")


def sh(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"{' '.join(args)} failed")
    return result.stdout


def fetch_report(repo: str, release: str | None) -> dict | None:
    tag = release
    try:
        if not tag:
            tag = sh("gh", "api", f"repos/{repo}/releases/latest", "--jq", ".tag_name").strip()
        tmp = Path(sh("mktemp", "-d").strip())
        sh("gh", "release", "download", tag, "--repo", repo, "--pattern", "scan-report.json",
           "--dir", str(tmp), "--clobber")
        report = json.loads((tmp / "scan-report.json").read_text())
        report["_tag"] = tag
        return report
    except (RuntimeError, FileNotFoundError, json.JSONDecodeError):
        return None


def badge(label: str, message: str, color: str, link: str) -> str:
    path = f"{urllib.parse.quote(label, safe='')}-{urllib.parse.quote(message, safe='')}-{color}"
    return f"[![{label}: {message}](https://img.shields.io/badge/{path})]({link})"


def render(report: dict | None, repo: str, release: str | None) -> str:
    if not report or not report.get("files"):
        return "\n".join(
            [
                BEGIN,
                badge("AV scan", "report unavailable", "lightgrey",
                      f"https://github.com/{repo}/releases"),
                END,
            ]
        )

    files = report["files"]
    total = len(files)
    detected = sum(1 for f in files if f.get("status") == "detected")
    tag = report.get("_tag") or release or "latest"
    report_url = f"https://github.com/{repo}/releases/download/{tag}/scan-report.md"

    lines = [BEGIN]
    for name in SCANNERS:
        done = sum(1 for f in files if f.get(name, {}).get("status") == "completed")
        if done == total:
            color, message = "brightgreen", f"{done}/{total}"
        elif done:
            color, message = "yellow", f"{done}/{total} partial"
        else:
            color, message = "lightgrey", "unavailable"
        label = "VirusTotal" if name == "virustotal" else "MetaDefender"
        lines.append(badge(label, message, color, report_url))

    if detected:
        lines.append(badge("malware", f"{detected}/{total} detected", "red", report_url))
    else:
        lines.append(badge("malware", "0 detections", "brightgreen", report_url))

    lines.append(END)
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="rusnino/iperf3-builds")
    parser.add_argument("--release", default=None)
    args = parser.parse_args()

    readme = README.read_text()
    if BEGIN not in readme or END not in readme:
        print(f"ERROR: {BEGIN} / {END} markers missing from README.md", file=sys.stderr)
        return 1

    before, rest = readme.split(BEGIN, 1)
    _, after = rest.split(END, 1)

    report = fetch_report(args.repo, args.release)
    block = render(report, args.repo, args.release)
    README.write_text(before + block + after)
    print(f"README badges updated from {'the scan report' if report else 'no report (neutral state)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
