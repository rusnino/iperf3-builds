#!/usr/bin/env python3
"""Submit artifact hashes/files to VirusTotal and a secondary scanner.

Environment variables:
    VT_API_KEY          VirusTotal API v3 key (optional).
    METADEFENDER_API_KEY    MetaDefender Cloud API v4 key (optional).

Usage:
    scripts/scan-virustotal.py <manifest.json> <output_dir>
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import urllib.request
import urllib.error

VT_API_KEY = os.environ.get("VT_API_KEY", "")
METADEFENDER_API_KEY = os.environ.get("METADEFENDER_API_KEY", "")
VT_SLEEP_SECONDS = 15  # public free-tier limit is 4 lookups/minute
METADEFENDER_SLEEP_SECONDS = 1


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _http_json(method: str, url: str, headers: dict, data: Any = None, timeout: int = 60) -> tuple:
    """Return (status_code, parsed_json_or_none, raw_body_or_error)."""
    req = urllib.request.Request(url, method=method, data=data)
    for key, value in headers.items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            try:
                return resp.status, json.loads(body), None
            except json.JSONDecodeError:
                return resp.status, None, body.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = None
        return exc.code, payload, body
    except urllib.error.URLError as exc:
        return 0, None, str(exc)


def _vt_sleep():
    time.sleep(VT_SLEEP_SECONDS)


def _metadefender_sleep():
    time.sleep(METADEFENDER_SLEEP_SECONDS)


def _vt_headers() -> dict:
    return {"x-apikey": VT_API_KEY, "accept": "application/json"}


def _metadefender_headers() -> dict:
    return {"apikey": METADEFENDER_API_KEY, "accept": "application/json"}


def _vt_analysis_stats(attrs: dict) -> dict:
    stats = attrs.get("last_analysis_stats", {})
    return {
        "status": "completed",
        "harmless": int(stats.get("harmless", 0)),
        "malicious": int(stats.get("malicious", 0)),
        "suspicious": int(stats.get("suspicious", 0)),
        "undetected": int(stats.get("undetected", 0)),
        "timeout": int(stats.get("timeout", 0)),
        "confirmed-timeout": int(stats.get("confirmed-timeout", 0)),
        "failure": int(stats.get("failure", 0)),
        "type-unsupported": int(stats.get("type-unsupported", 0)),
    }


def virustotal_lookup_or_submit(file_path: Path, sha256: str) -> dict:
    if not VT_API_KEY:
        return {"status": "skipped", "reason": "VT_API_KEY not configured"}

    url = f"https://www.virustotal.com/api/v3/files/{sha256}"
    status, payload, error = _http_json("GET", url, _vt_headers())

    if status == 200 and isinstance(payload, dict):
        attrs = payload.get("data", {}).get("attributes", {})
        result = _vt_analysis_stats(attrs)
        result["permalink"] = payload.get("data", {}).get("links", {}).get("item", "")
        result["method"] = "lookup"
        return result

    if status == 404:
        # Not previously seen: upload the file.
        with file_path.open("rb") as fp:
            boundary = "----PythonBoundaryScanArtifact"
            body_prefix = (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="file"; filename="{file_path.name}"\r\n'
                f"Content-Type: application/gzip\r\n\r\n"
            ).encode("utf-8")
            body_suffix = f"\r\n--{boundary}--\r\n".encode("utf-8")
            body = body_prefix + fp.read() + body_suffix

        headers = _vt_headers()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        status, payload, error = _http_json(
            "POST", "https://www.virustotal.com/api/v3/files", headers, data=body
        )
        _vt_sleep()

        if status == 200 and isinstance(payload, dict):
            analysis_id = payload.get("data", {}).get("id", "")
            if analysis_id:
                return _virustotal_poll_analysis(analysis_id)

        return {"status": "error", "method": "upload", "http_status": status, "error": error or payload}

    return {"status": "error", "method": "lookup", "http_status": status, "error": error or payload}


def _virustotal_poll_analysis(analysis_id: str, attempts: int = 10, interval: int = 15) -> dict:
    url = f"https://www.virustotal.com/api/v3/analyses/{analysis_id}"
    for _ in range(attempts):
        status, payload, error = _http_json("GET", url, _vt_headers())
        if status == 200 and isinstance(payload, dict):
            analysis_status = payload.get("data", {}).get("attributes", {}).get("status", "")
            if analysis_status == "completed":
                stats = payload.get("data", {}).get("attributes", {}).get("stats", {})
                result = {
                    "status": "completed",
                    "harmless": int(stats.get("harmless", 0)),
                    "malicious": int(stats.get("malicious", 0)),
                    "suspicious": int(stats.get("suspicious", 0)),
                    "undetected": int(stats.get("undetected", 0)),
                    "timeout": int(stats.get("timeout", 0)),
                    "permalink": f"https://www.virustotal.com/gui/file-analysis/{analysis_id}",
                    "method": "upload",
                }
                return result
        _vt_sleep()
    return {"status": "timeout", "method": "upload", "analysis_id": analysis_id}


def metadefender_lookup(sha256: str) -> dict:
    if not METADEFENDER_API_KEY:
        return {"status": "skipped", "reason": "METADEFENDER_API_KEY not configured"}

    url = f"https://api.metadefender.com/v4/hash/{sha256}"
    status, payload, error = _http_json("GET", url, _metadefender_headers())
    _metadefender_sleep()

    if status == 200 and isinstance(payload, dict):
        scan_results = payload.get("scan_results", {})
        return {
            "status": "completed",
            "total_avs": int(scan_results.get("total_avs", 0)),
            "total_detected": int(scan_results.get("total_detected", 0)),
            "scan_all_result_a": scan_results.get("scan_all_result_a", ""),
            "permalink": payload.get("data", {}).get("permalink", "") or payload.get("permalink", ""),
        }

    return {"status": "error", "http_status": status, "error": error or payload}


def scan_manifest(manifest_path: Path, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("r", encoding="utf-8") as fp:
        manifest = json.load(fp)

    results = []
    for item in manifest:
        file_path = Path(item["file"])
        sha256 = item["sha256"]
        print(f"Scanning {file_path.name} ({sha256})...", file=sys.stderr)

        vt_result = virustotal_lookup_or_submit(file_path, sha256)
        _vt_sleep()

        md_result = metadefender_lookup(sha256)

        results.append(
            {
                "file": str(file_path),
                "basename": item["basename"],
                "sha256": sha256,
                "size": item["size"],
                "virustotal": vt_result,
                "metadefender": md_result,
            }
        )

    report = {
        "generated_at": _now(),
        "scanners": {
            "virustotal": {"configured": bool(VT_API_KEY)},
            "metadefender": {"configured": bool(METADEFENDER_API_KEY)},
        },
        "files": results,
    }

    json_path = output_dir / "scan-report.json"
    md_path = output_dir / "scan-report.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(_render_markdown(report), encoding="utf-8")
    return json_path


def _render_markdown(report: dict) -> str:
    lines = [
        "# Release artifact antivirus scan report",
        "",
        f"Generated at: {report['generated_at']}",
        "",
        "## Configuration",
        "",
        f"- VirusTotal: {'configured' if report['scanners']['virustotal']['configured'] else 'not configured'}",
        f"- MetaDefender Cloud: {'configured' if report['scanners']['metadefender']['configured'] else 'not configured'}",
        "",
        "## Results",
        "",
        "| File | SHA-256 | Size | VirusTotal | MetaDefender |",
        "|---|---|---:|---|---|",
    ]

    for f in report["files"]:
        vt = f["virustotal"]
        md = f["metadefender"]
        vt_cell = _fmt_vt(vt)
        md_cell = _fmt_md(md)
        lines.append(f"| {f['basename']} | `{f['sha256']}` | {f['size']} | {vt_cell} | {md_cell} |")

    lines.extend(
        [
            "",
            "## Details",
            "",
        ]
    )
    for f in report["files"]:
        lines.append(f"### {f['basename']}")
        lines.append("")
        lines.append(f"- SHA-256: `{f['sha256']}`")
        lines.append(f"- Size: {f['size']} bytes")
        lines.append(f"- VirusTotal: {json.dumps(f['virustotal'], indent=2)}")
        lines.append(f"- MetaDefender: {json.dumps(f['metadefender'], indent=2)}")
        lines.append("")

    flagged = [
        f
        for f in report["files"]
        if f["virustotal"].get("malicious", 0) > 0
        or f["virustotal"].get("suspicious", 0) > 0
        or f["metadefender"].get("total_detected", 0) > 0
    ]
    if flagged:
        lines.append("## ⚠️ Flagged artifacts")
        lines.append("")
        for f in flagged:
            lines.append(f"- {f['basename']} — review the detailed scanner output above.")
        lines.append("")
    else:
        lines.append("## Summary")
        lines.append("")
        lines.append("No scanner reported malicious or suspicious detections.")
        lines.append("")

    return "\n".join(lines) + "\n"


def _fmt_vt(vt: dict) -> str:
    if vt.get("status") == "skipped":
        return f"skipped ({vt.get('reason', 'no key')})"
    if vt.get("status") == "error":
        return f"error (HTTP {vt.get('http_status', 'N/A')})"
    if vt.get("status") == "timeout":
        return "timeout"
    total = sum(
        vt.get(k, 0) for k in ("harmless", "malicious", "suspicious", "undetected", "timeout")
    )
    return f"{vt.get('malicious', 0)}/{total} malicious (VT)"


def _fmt_md(md: dict) -> str:
    if md.get("status") == "skipped":
        return f"skipped ({md.get('reason', 'no key')})"
    if md.get("status") == "error":
        return f"error (HTTP {md.get('http_status', 'N/A')})"
    total = md.get("total_avs", 0)
    detected = md.get("total_detected", 0)
    return f"{detected}/{total} detected (MetaDefender)"


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    manifest_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    scan_manifest(manifest_path, output_dir)
