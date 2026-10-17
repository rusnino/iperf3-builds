# Security hardening and release artifact verification

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automated antivirus scanning of release binaries and complete a security audit of the GitHub Actions workflow so users can trust the provenance and integrity of published artifacts.

**Architecture:** A standalone `scan-artifacts.sh` helper runs after the release job, submits artifact hashes to VirusTotal and a secondary scanner, and stores scan results in a machine-readable report attached to the release. A separate workflow-security audit pins all third-party actions to commit hashes, restricts permissions, validates inputs, and documents the results in `SECURITY.md`.

**Tech Stack:** GitHub Actions, VirusTotal API v3, optional secondary scanner (e.g., MetaDefender or Jotti), cosign/Sigstore optional, shell, Python 3.

**Spec:** docs/superpowers/specs/2026-10-17-iperf3-builds-platform-coverage.md (section 12)

## Global Constraints

- Free GitHub Actions runners only.
- Secrets must be optional for build jobs; required only for release/scanner jobs.
- Do not break existing Linux static/dynamic/macOS release pipeline.
- Preserve existing asset naming and SHA256SUMS generation.
- Scanner results must be reproducible and stored alongside releases.
- If a scanner API rate-limits or fails, the release must not be silently published without a record.

## Review Focus

1. **Scanner API abuse / rate limits:** VirusTotal free tier allows only 4 lookups/min. A naive parallel loop will fail. Caught by throttled submission with retry and by storing pending status.
2. **Secret leakage:** API keys must never appear in logs or shell history. Caught by passing them only through `secrets` and by a test that greps logs for the key.
3. **Workflow supply-chain poisoning:** using `@main` or mutable action tags lets an attacker replace an action. Caught by pinning all actions to immutable commit hashes and documenting the audit.
4. **False confidence from one scanner:** a single AV miss is not a clean bill. Caught by requiring at least two independent scanners and reporting both.
5. **Tainted artifact published before scan:** scanning after upload means a malicious artifact could be briefly public. Caught by attaching scan reports as a follow-up release asset and documenting the window.

---

### Task 1: Audit and harden GitHub Actions workflow

**Files:**
- Modify: `.github/workflows/build-release.yml`
- Create: `SECURITY.md`

**Interfaces:**
- Consumes: existing workflow steps and third-party actions.
- Produces: pinned action hashes, restricted permissions, documented security posture.

- [ ] **Step 1: Inventory all third-party actions**

Run:
```bash
grep -E "uses:\s+[^/]+/" .github/workflows/build-release.yml | sort -u
```

Expected output: list of actions like `actions/checkout@v5`, `actions/upload-artifact@v6`, etc.

- [ ] **Step 2: Replace mutable tags with immutable commit hashes**

For each third-party action, find the commit SHA corresponding to the currently used tag and replace `uses: owner/name@tag` with `uses: owner/name@sha256#tag`.

Keep a comment with the human-readable tag, e.g.:
```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4
```

Expected: `grep -v '#' .github/workflows/build-release.yml | grep -E "uses:.*@[^0-9a-f]{40,}"` returns nothing.

- [ ] **Step 3: Apply least-privilege permissions**

Set top-level `permissions: {}` and grant only the minimal permissions per job:
- `build-*` jobs: `contents: read`.
- `release` job: `contents: write` (needed to upload assets).
- `retry-failed-jobs` job: `actions: write`.

Expected: no job has broader permissions than required.

- [ ] **Step 4: Validate untrusted workflow inputs**

Ensure the version validation step rejects `/`, `\`, `..`, and any non-tag-like characters before any checkout or network call.

Add a test by running locally:
```bash
VERSION='../etc/passwd' bash -c 'source .github/workflows/build-release.yml'
```

This is hard to unit-test outside GHA; instead run the validation snippet directly:
```bash
for bad in '../x' 'x/y' 'x\\y' '..x' ''; do
  echo "$bad" | grep -E '[/\\]|\.\.' && echo "REJECT: $bad" || echo "OK-ish: $bad"
done
```

Expected: all dangerous inputs are identified as rejected.

- [ ] **Step 5: Document security posture in SECURITY.md**

Create `SECURITY.md` covering:
- how binaries are built (Zig + OpenSSL from source, no third-party prebuilt toolchains);
- how secrets are used (only `GITHUB_TOKEN` and optional scanner API keys);
- action pinning policy;
- how to report security issues;
- where to find scan results.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/build-release.yml SECURITY.md
git commit -m "ci: pin actions, restrict permissions, and document security posture"
```

---

### Task 2: Add antivirus scanning helper script

**Files:**
- Create: `scripts/scan-artifacts.sh`
- Create: `scripts/scan-virustotal.py` (or inline Python in shell)

**Interfaces:**
- Consumes: local `artifacts/` directory with `iperf3-*.tar.gz` files, `VT_API_KEY` environment variable.
- Produces: `scan-report.json` and `scan-report.md` with per-file hash, scan status, and detected/missing engines.

- [ ] **Step 1: Implement artifact hash collection**

`scan-artifacts.sh` computes SHA-256 of each `artifacts/iperf3-*.tar.gz` file and writes a temporary manifest:
```json
{
  "file": "artifacts/iperf3-3.22-linux-x86_64-static.tar.gz",
  "sha256": "...",
  "size": 1234
}
```

- [ ] **Step 2: Implement VirusTotal submission/lookup with rate limiting**

Use VirusTotal API v3:
- First `GET https://www.virustotal.com/api/v3/files/{sha256}` to check if already scanned.
- If 404, `POST https://www.virustotal.com/api/v3/files` with the file bytes.
- Wait and poll `GET /analyses/{id}` until status is `completed`.
- Throttle requests to respect the public API limit (max 4/min for free key). Sleep 15s between submissions.

Store for each file:
- `virustotal_permalink` (or analysis URL)
- `virustotal_harmless`, `virustotal_malicious`, `virustotal_suspicious`, `virustotal_undetected`
- `virustotal_status`

- [ ] **Step 3: Implement secondary scanner**

Add support for a second scanner. Choose one of:
- **MetaDefender Cloud** (requires `METADEFENDER_API_KEY`); or
- **Jotti's malware scan** (no API, not automatable — skip); or
- **Hybrid Analysis / MalwareBazaar** (hash-only lookup).

For simplicity and reliability, use MetaDefender Cloud hash lookup (`GET /v4/hash/{hash}`) as the secondary. If no key is provided, the secondary scanner reports `skipped: no API key`.

- [ ] **Step 4: Generate human-readable scan report**

`scan-report.md` must contain:
- timestamp;
- list of scanned files with hashes;
- per-file VirusTotal and secondary results;
- a clear statement if any engine flagged a file.

- [ ] **Step 5: Test the scanner against a known-clean artifact**

Run locally with a built archive:
```bash
VT_API_KEY=${VT_API_KEY:-} ./scripts/scan-artifacts.sh artifacts/
```

Expected: `scan-report.json` is created, all files show `malicious: 0`, and rate-limiting does not cause failures.

- [ ] **Step 6: Commit**

```bash
git add scripts/scan-artifacts.sh scripts/scan-virustotal.py
git commit -m "feat: add antivirus scanning helper for release artifacts"
```

---

### Task 3: Integrate scanning into release workflow

**Files:**
- Modify: `.github/workflows/build-release.yml`

**Interfaces:**
- Consumes: release artifacts, `VT_API_KEY` secret.
- Produces: `scan-report.json` and `scan-report.md` uploaded to the release.

- [ ] **Step 1: Add scan job after release**

Add a new job `scan-release-artifacts` that:
- `needs: release`
- downloads release assets into `artifacts/`
- runs `scripts/scan-artifacts.sh artifacts/`
- uploads `scan-report.json` and `scan-report.md` back to the release as assets.

Make the job `continue-on-error: true` only if you want a scanner outage to block nothing; otherwise let it fail the release. Per the spec, failures must not be hidden: set `continue-on-error: false`.

- [ ] **Step 2: Add secrets documentation**

In `SECURITY.md` or workflow comments, document:
- `VT_API_KEY` — VirusTotal API key (free tier sufficient).
- `METADEFENDER_API_KEY` — optional secondary scanner key.

- [ ] **Step 3: Validate workflow YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-release.yml'))"
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build-release.yml SECURITY.md
git commit -m "ci: run antivirus scan after release and publish report"
```

---

### Task 4: Optional artifact signing and SLSA provenance (stretch)

**Files:**
- Modify: `.github/workflows/build-release.yml`
- Create: `scripts/generate-provenance.sh` (optional)

**Interfaces:**
- Consumes: release artifacts, Sigstore identity.
- Produces: `.sig` signatures and/or SLSA provenance attestation.

- [ ] **Step 1: Evaluate cosign keyless signing**

Add a job `sign-release` that uses `sigstore/cosign-installer` and `cosign sign-blob` in keyless mode (works with GitHub OIDC on public repos). Sign each `iperf3-*.tar.gz` and upload `.sig` files.

- [ ] **Step 2: Document how users verify signatures**

Add a `Verifying signatures` section to `README.md` or `SECURITY.md` with commands:
```bash
cosign verify-blob \
  --signature iperf3-3.22-linux-x86_64-static.tar.gz.sig \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/rusnino/iperf3-builds/.github/workflows/build-release.yml@refs/tags/' \
  iperf3-3.22-linux-x86_64-static.tar.gz
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-release.yml SECURITY.md README.md
git commit -m "feat: keyless cosign signatures for release artifacts"
```

---

## Self-review checklist

- [x] Spec coverage: section 12 (security and trust) is represented by Tasks 1-4.
- [ ] Step scan: each step is one actionable item with a checkable result.
- [ ] Type consistency: script/env names (`VT_API_KEY`, `METADEFENDER_API_KEY`, `scan-report.json`) are consistent across tasks.
- [ ] Review Focus: each risk has a verification step (rate-limit test, secret grep, pinned-action grep, two-scanner report, scan-after-release documentation).
- [ ] Proportion: plan is shorter than the spec; bodies left to implementer except exact values.
