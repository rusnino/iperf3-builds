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
VERSION = os.environ.get("VERSION", "")
WORKFLOW_REF = os.environ.get("WORKFLOW_REF", "")
VT_LOOKUP_INTERVAL_SECONDS = 15  # public API: 4 requests/minute, 500/day
VT_POLL_INTERVAL_SECONDS = VT_LOOKUP_INTERVAL_SECONDS
VT_POLL_ATTEMPTS = 24  # ~6 minutes per artifact at 15s, per scanning phase
METADEFENDER_SLEEP_SECONDS = 1


def _signature_identity() -> str:
    """Expected cosign certificate identity for this release.

    Signature subjects are workflow files, not tags, so the identity is the
    exact `build-release.yml` ref that produced the artifacts.
    """
    if WORKFLOW_REF:
        return WORKFLOW_REF
    return ""


SIGNATURE_IDENTITY = _signature_identity()


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
    time.sleep(VT_LOOKUP_INTERVAL_SECONDS)


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

    if status in (401, 403):
        return {"status": "skipped", "reason": "invalid or unauthorized VirusTotal API key"}

    if status == 404:
        # Not previously seen: upload the file. VirusTotal queues the analysis
        # and returns immediately; poll until the engine set reports back.
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
                return _virustotal_wait_for_analysis(sha256, analysis_id)

        return {"status": "error", "method": "upload", "http_status": status, "error": error or payload}

    return {"status": "error", "method": "lookup", "http_status": status, "error": error or payload}


def _virustotal_ready(stats: dict) -> bool:
    """True once the engine set produced a verdict (0 engines == still queued)."""
    return sum(int(stats.get(k, 0)) for k in ("harmless", "malicious", "suspicious", "undetected")) > 0


def _virustotal_wait_for_analysis(
    sha256: str, analysis_id: str, attempts: int = VT_POLL_ATTEMPTS, interval: int = VT_POLL_INTERVAL_SECONDS
) -> dict:
    """Poll the analysis, then fall back to the file report for the final stats."""
    url = f"https://www.virustotal.com/api/v3/analyses/{analysis_id}"
    for _ in range(attempts):
        status, payload, error = _http_json("GET", url, _vt_headers())
        if status == 200 and isinstance(payload, dict):
            attrs = payload.get("data", {}).get("attributes", {})
            if attrs.get("status") == "completed" and _virustotal_ready(attrs.get("stats", {})):
                result = _vt_analysis_stats({"last_analysis_stats": attrs.get("stats", {})})
                result["permalink"] = f"https://www.virustotal.com/gui/file-analysis/{analysis_id}"
                result["method"] = "upload"
                return result
        time.sleep(interval)

    # Some scans stay "queued" for a long time; the file report is authoritative
    # once enough engines have reported.
    for _ in range(attempts):
        status, payload, error = _http_json("GET", f"https://www.virustotal.com/api/v3/files/{sha256}", _vt_headers())
        if status == 200 and isinstance(payload, dict):
            attrs = payload.get("data", {}).get("attributes", {})
            stats = attrs.get("last_analysis_stats", {})
            if _virustotal_ready(stats):
                result = _vt_analysis_stats(attrs)
                result["permalink"] = payload.get("data", {}).get("links", {}).get("item", "")
                result["method"] = "upload"
                return result
        time.sleep(interval)

    return {
        "status": "timeout",
        "method": "upload",
        "analysis_id": analysis_id,
        "reason": "analysis did not finish in time",
    }


def _metadefender_result(scan_results: dict, payload: dict) -> dict:
    return {
        "status": "completed",
        "total_avs": int(scan_results.get("total_avs", 0)),
        "total_detected": int(scan_results.get("total_detected", 0)),
        "scan_all_result_a": scan_results.get("scan_all_result_a", ""),
        "permalink": payload.get("data", {}).get("permalink", "") or payload.get("permalink", ""),
    }


def _metadefender_done(scan_results: dict) -> bool:
    # MetaDefender reports scan_all_result_a for queued/in-progress scans too
    # ("In Progress"), with total_avs == 0. Only trust a finished verdict.
    verdict = str(scan_results.get("scan_all_result_a", ""))
    return int(scan_results.get("total_avs", 0)) > 0 and verdict not in ("", "In Progress")


def metadefender_scan(file_path: Path, sha256: str) -> dict:
    if not METADEFENDER_API_KEY:
        return {"status": "skipped", "reason": "METADEFENDER_API_KEY not configured"}

    url = f"https://api.metadefender.com/v4/hash/{sha256}"
    status, payload, error = _http_json("GET", url, _metadefender_headers())
    _metadefender_sleep()

    if status == 200 and isinstance(payload, dict):
        scan_results = payload.get("scan_results", {})
        if _metadefender_done(scan_results):
            result = _metadefender_result(scan_results, payload)
            result["method"] = "lookup"
            return result
        return {"status": "pending", "method": "lookup", "reason": "hash scan still in progress"}

    if status in (401, 403):
        return {"status": "skipped", "reason": "invalid or unauthorized MetaDefender API key"}

    if status == 404:
        # Hash not known to MetaDefender: upload the file for scanning.
        file_data = file_path.read_bytes()
        upload_headers = _metadefender_headers()
        upload_headers["filename"] = file_path.name
        upload_headers["Content-Type"] = "application/octet-stream"
        upload_headers["Content-Length"] = str(len(file_data))
        up_status, up_payload, up_error = _http_json(
            "POST", "https://api.metadefender.com/v4/file", upload_headers, data=file_data
        )
        _metadefender_sleep()

        if up_status in (401, 403):
            return {"status": "skipped", "reason": "invalid or unauthorized MetaDefender API key"}
        if up_status == 200 and isinstance(up_payload, dict):
            data_id = up_payload.get("data_id", "")
            if data_id:
                return _metadefender_poll(data_id)

        return {"status": "error", "method": "upload", "http_status": up_status, "error": up_error or up_payload}

    return {"status": "error", "method": "lookup", "http_status": status, "error": error or payload}


def _metadefender_poll(data_id: str, attempts: int = 30, interval: int = 10) -> dict:
    url = f"https://api.metadefender.com/v4/file/{data_id}"
    return _metadefender_wait(url, attempts, interval, method="upload", extra={"data_id": data_id})


def _metadefender_poll_by_hash(sha256: str, attempts: int = 30, interval: int = 10) -> dict:
    url = f"https://api.metadefender.com/v4/hash/{sha256}"
    return _metadefender_wait(url, attempts, interval, method="lookup")


def _metadefender_wait(url: str, attempts: int, interval: int, method: str, extra: dict | None = None) -> dict:
    last_verdict = ""
    for _ in range(attempts):
        status, payload, error = _http_json("GET", url, _metadefender_headers())
        _metadefender_sleep()

        if status in (401, 403):
            return {"status": "skipped", "reason": "invalid or unauthorized MetaDefender API key"}
        if status == 200 and isinstance(payload, dict):
            scan_results = payload.get("scan_results", {})
            last_verdict = str(scan_results.get("scan_all_result_a", ""))
            if _metadefender_done(scan_results):
                result = _metadefender_result(scan_results, payload)
                result["method"] = method
                return result
        time.sleep(interval)

    result = {
        "status": "timeout",
        "method": method,
        "last_verdict": last_verdict,
        "reason": "scan did not finish in time",
    }
    result.update(extra or {})
    return result


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

        md_result = metadefender_scan(file_path, sha256)
        if md_result.get("status") == "pending":
            # Cached hash scan started by someone else: wait for the verdict.
            md_result = _metadefender_poll_by_hash(sha256)

        results.append(
            {
                "file": str(file_path),
                "basename": item["basename"],
                "sha256": sha256,
                "size": item["size"],
                "status": _artifact_status(vt_result, md_result),
                "virustotal": vt_result,
                "metadefender": md_result,
            }
        )

    report = {
        "generated_at": _now(),
        "version": VERSION,
        "signature_identity": SIGNATURE_IDENTITY,
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
    _summarise(results)
    return json_path


def _artifact_status(vt: dict, md: dict) -> str:
    # Timeouts and errors are reported per artifact so they stay visible, even
    # when the other scanner produced a usable verdict.
    results = (vt, md)
    for result in results:
        if result.get("status") == "error":
            return "scanner-error"
    for result in results:
        if result.get("status") == "timeout":
            return "scanner-timeout"
    if all(result.get("status") == "skipped" for result in results):
        return "not-scanned"

    detected = vt.get("malicious", 0) + vt.get("suspicious", 0) + md.get("total_detected", 0)
    if detected > 0:
        return "detected"

    vt_total = sum(vt.get(k, 0) for k in ("harmless", "undetected", "confirmed-timeout"))
    md_total = md.get("total_avs", 0)
    if vt.get("status") == "completed" and vt_total > 0:
        return "clean"
    if md.get("status") == "completed" and md_total > 0:
        return "clean"
    # Scanners answered but no engine produced a verdict (e.g. MetaDefender
    # still reports 0 engines while its verdict says "In Progress").
    return "indeterminate"


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
        "| File | SHA-256 | Size | VirusTotal | MetaDefender | Status |",
        "|---|---|---:|---|---|---|",
    ]

    for f in report["files"]:
        vt = f["virustotal"]
        md = f["metadefender"]
        vt_cell = _fmt_vt(vt)
        md_cell = _fmt_md(md)
        lines.append(
            f"| {f['basename']} | `{f['sha256']}` | {f['size']} | {vt_cell} | {md_cell} | {f.get('status', 'unknown')} |"
        )

    if report.get("version"):
        lines.extend(["", "## Verification", ""])
        identity = report.get("signature_identity") or ""
        archive = report["files"][0]["basename"] if report["files"] else "<archive>.tar.gz"
        lines.append("Each archive is signed with Sigstore/cosign in keyless mode. Verify with:")
        lines.append("")
        lines.append("```bash")
        lines.append("cosign verify-blob \\")
        lines.append(f"  --signature {archive}.sig \\")
        lines.append(f"  --certificate {archive}.cert \\")
        lines.append("  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\")
        if identity:
            lines.append(f"  --certificate-identity '{identity}' \\")
        else:
            lines.append("  --certificate-identity-regexp '<workflow identity from the certificate>' \\")
        lines.append(f"  {archive}")
        lines.append("```")

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

    flagged = [f for f in report["files"] if f.get("status") == "detected"]
    failed = [f for f in report["files"] if f.get("status") in ("scanner-error", "scanner-timeout")]
    unclear = [
        f for f in report["files"] if f.get("status") in ("not-scanned", "indeterminate")
    ]
    if flagged:
        lines.append("## ⚠️ Flagged artifacts")
        lines.append("")
        for f in flagged:
            lines.append(f"- {f['basename']} — review the detailed scanner output above.")
        lines.append("")
    if failed:
        lines.append("## Scanner errors")
        lines.append("")
        for f in failed:
            lines.append(f"- {f['basename']} — {f['status']}: a scanner did not return a result.")
        lines.append("")
    if unclear:
        lines.append("## ⚠️ Incomplete scans")
        lines.append("")
        unscanned = [f for f in unclear if f["status"] == "not-scanned"]
        if unscanned:
            lines.append(
                f"- {len(unscanned)} artifact(s) were not scanned by any engine "
                "(scanner API keys missing or invalid)."
            )
        for f in unclear:
            if f["status"] == "indeterminate":
                lines.append(f"- {f['basename']} — no engine returned a verdict yet.")
        lines.append("")
    if not flagged and not failed and not unclear:
        lines.append("## Summary")
        lines.append("")
        lines.append("All artifacts were scanned and no scanner reported malicious or suspicious detections.")
        lines.append("")

    return "\n".join(lines) + "\n"


def _summarise(results: list) -> None:
    counts: dict = {}
    for item in results:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
    print("Scan summary: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())), file=sys.stderr)


def _fmt_vt(vt: dict) -> str:
    if vt.get("status") == "skipped":
        return f"skipped ({vt.get('reason', 'no key')})"
    if vt.get("status") == "error":
        return f"error (HTTP {vt.get('http_status', 'N/A')})"
    if vt.get("status") == "timeout":
        return "timeout"
    total = sum(
        vt.get(k, 0)
        for k in ("harmless", "malicious", "suspicious", "undetected", "timeout", "confirmed-timeout")
    )
    return f"{vt.get('malicious', 0)}/{total} malicious (VT)"


def _fmt_md(md: dict) -> str:
    if md.get("status") == "skipped":
        return f"skipped ({md.get('reason', 'no key')})"
    if md.get("status") == "error":
        return f"error (HTTP {md.get('http_status', 'N/A')})"
    if md.get("status") == "timeout":
        return "timeout"
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
