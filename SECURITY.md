# Security policy and release trust

This document describes how we build, verify, and secure release artifacts for
`iperf3-builds`. It is intended for users who want to understand provenance and
for anyone reporting a security issue.

## Build provenance

All Linux static binaries are cross-compiled with the official [Zig](https://ziglang.org/)
toolchain (`zig cc`) and statically linked against [musl libc](https://musl.libc.org/).
The Zig release used for a build is recorded in every archive's `MANIFEST.json`
along with the exact target triple, CPU/ABI metadata, and OpenSSL version (for
`-auth` builds).

OpenSSL for `-auth` archives is built from upstream source for every target;
we do not redistribute prebuilt OpenSSL toolchains.

Dynamic Linux builds run in an AlmaLinux 8 container to target glibc 2.28+
systems. macOS universal2 binaries are built on GitHub-hosted macOS runners from
upstream iperf3 source.

## GitHub Actions security

- All third-party actions are pinned to immutable commit SHAs. The human-readable
  tag is kept in a trailing comment (e.g. `actions/checkout@<sha> # v5`).
- The workflow uses least-privilege `permissions`:
  - build jobs: `contents: read`
  - release job: `contents: write`
  - retry job: `actions: write`
- Untrusted workflow inputs (the iperf3 version/tag) are validated before any
  checkout or network call. Inputs containing path separators, parent-directory
  references, whitespace, or characters outside a safe tag alphabet are rejected.
- No secrets are logged. The only required secret is `GITHUB_TOKEN`; optional
  scanner API keys are used only in the release scan job.

## Antivirus scanning

After each release, the `scan-release-artifacts` job submits every published
archive to two independent, multi-engine services:

- **VirusTotal** (primary) — hash/file lookup and submission via VirusTotal API v3.
- **MetaDefender Cloud** (secondary) — hash lookup, falling back to uploading the
  file for scanning via MetaDefender Cloud API v4.

Results are stored in `scan-report.json` and a human-readable `scan-report.md`,
both of which are uploaded back to the GitHub release. Every archive row carries
a `status`:

- `clean` — at least one engine scanned the file and nothing was flagged;
- `detected` — at least one engine flagged the file;
- `scanner-error` / `scanner-timeout` — a scanner returned an error or did not
  finish;
- `not-scanned` — neither scanner could run (missing/invalid API keys);
- `indeterminate` — the scanners answered but no engine produced a verdict yet.
  The report summary states explicitly how many artifacts fall into the
  `not-scanned` and `indeterminate` groups.

Scan jobs run *after* release creation, so a brief window exists where assets
are public before the report is attached; this window is documented in the
release notes.

If you find an engine flagging a release archive, please open a security issue
(see below) and include the scanner report and file hash.

## Verifying signatures

Release archives are signed with [Sigstore/cosign](https://www.sigstore.dev/) in
keyless mode from the GitHub Actions workflow. Each archive has a matching
`.sig` and `.cert` file attached to the release. The certificate subject is the
workflow that built the release (`build-release.yml`), not a tag, so use
`--certificate-identity` with the exact ref used for the build:

```bash
# Releases built from the default branch:
IDENTITY="https://github.com/rusnino/iperf3-builds/.github/workflows/build-release.yml@refs/heads/main"

# Releases built while testing a feature branch:
# IDENTITY="https://github.com/rusnino/iperf3-builds/.github/workflows/build-release.yml@refs/heads/<branch>"

cosign verify-blob \
  --signature iperf3-3.22-linux-x86_64-static.tar.gz.sig \
  --certificate iperf3-3.22-linux-x86_64-static.tar.gz.cert \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "${IDENTITY}" \
  iperf3-3.22-linux-x86_64-static.tar.gz
```

To discover the identity without guessing, inspect the certificate subject:

```bash
cosign verify-blob --certificate <archive>.cert --signature <archive>.sig <archive>
```

If you only want to ensure the signature came from this repository's workflow
at *any* ref, use `--certificate-identity-regexp` with a `.*` suffix:

```bash
--certificate-identity-regexp '^https://github\.com/rusnino/iperf3-builds/\.github/workflows/build-release\.yml@.*'
```

The same command is embedded in every release's `scan-report.md`.

## Reporting security issues

Please report sensitive security concerns by opening a GitHub issue with the
title prefix `[SECURITY]` or by contacting the repository maintainers through
GitHub private communication. Do not disclose vulnerabilities in public issues
until a fix is released.
