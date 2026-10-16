# Future enhancements for iperf3-builds

Saved from user request. These items are planned for implementation.

- [x] Add `-auth` builds with OpenSSL so RSA authentication works.
- [ ] Reduce artifact retention period (e.g. 30 days) in GitHub Actions to avoid storing built artifacts twice.
- [ ] Add localized release notes (e.g. Russian/Chinese summary) alongside upstream English notes.
- [ ] Sign releases with Sigstore/cosign (or GPG) so users can verify archive integrity.
- [ ] Publish a Docker/OCI image containing iperf3 in addition to tar archives.
- [ ] Auto-deprecate outdated pre-release / rc builds when a newer stable release exists.
- [ ] Auto-retry failed workflow jobs (limited attempts) to handle transient runner/network failures.

## Cross-platform builds under consideration

- x86 (i386 / x32) Linux
- x86_64 Linux (already done)
- ARM 32-bit Linux (armv7, armhf)
- ARM 64-bit Linux (aarch64)
- macOS Intel (x86_64)
- macOS Apple Silicon (arm64 / M1/M2/M3)
- Other Unix/BSD-like systems (non-Windows): FreeBSD, OpenBSD, NetBSD, Solaris/illumos

## Expanded platform matrix (matching `userdocs/iperf3-static`)

Goal: support the same breadth of targets.

- **Linux:** `aarch64`, `arm`, `armhf`, `armv7`, `x86`, `x86_64`, `mips`, `mipsel`, `mips64`, `mips64el`, `powerpc`, `ppc64le`, `s390x`, `riscv64`, `loongarch64`
- **Windows:** `x86_64` (Cygwin-based static build)
- **macOS:** `x86_64`, `arm64` (universal2)

Notes:
- Requires prebuilt OpenSSL for every Linux cross target.
- Windows build needs a Cygwin installer/setup step on a Windows runner.
- More architectures = longer CI queues; consider `fail-fast: false` and artifact-only dispatch option.
