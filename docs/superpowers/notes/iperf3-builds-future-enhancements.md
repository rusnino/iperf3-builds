# Future enhancements for iperf3-builds

Saved from user request. These items are planned for implementation.

- [ ] Reduce artifact retention period (e.g. 30 days) in GitHub Actions to avoid storing built artifacts twice.
- [ ] Add localized release notes (e.g. Russian/Chinese summary) alongside upstream English notes.
- [ ] Sign releases with Sigstore/cosign (or GPG) so users can verify archive integrity.
- [ ] Publish a Docker/OCI image containing iperf3 in addition to tar archives.
- [ ] Auto-deprecate outdated pre-release / rc builds when a newer stable release exists.

## Cross-platform builds under consideration

- x86 (i386 / x32) Linux
- x86_64 Linux (already done)
- ARM 32-bit Linux (armv7, armhf)
- ARM 64-bit Linux (aarch64)
- macOS Intel (x86_64)
- macOS Apple Silicon (arm64 / M1/M2/M3)
- Other Unix/BSD-like systems (non-Windows): FreeBSD, OpenBSD, NetBSD, Solaris/illumos
