# Future enhancements for iperf3-builds

Saved from user request. These items are planned for implementation.

- [x] Add `-auth` builds with OpenSSL so RSA authentication works.
- [x] Migrate Linux static cross builds from third-party `userdocs/qbt-musl-cross-make` toolchains and `userdocs/openssl` prebuilts to the official Zig toolchain (`zig cc`) and OpenSSL built from upstream source.
- [ ] Reduce artifact retention period (e.g. 30 days) in GitHub Actions to avoid storing built artifacts twice.
- [ ] Add localized release notes (e.g. Russian/Chinese summary) alongside upstream English notes.
- [ ] Sign releases with Sigstore/cosign (or GPG) so users can verify archive integrity.
- [ ] Publish a Docker/OCI image containing iperf3 in addition to tar archives.
- [ ] Auto-deprecate outdated pre-release / rc builds when a newer stable release exists.
- [x] Auto-retry failed workflow jobs (limited attempts) to handle transient runner/network failures.

## Cross-platform builds under consideration

- x86 (i386 / x32) Linux (done)
- x86_64 Linux (already done)
- ARM 32-bit Linux (armv7, armhf) (done)
- ARM 64-bit Linux (aarch64) (done)
- macOS Intel (x86_64) (done)
- macOS Apple Silicon (arm64 / M1/M2/M3) (done)
- Other Unix/BSD-like systems (non-Windows): FreeBSD, OpenBSD, NetBSD, Solaris/illumos (backlog)

## Stable Linux static platform matrix

- [x] **Linux:** `aarch64`, `arm`, `armhf`, `armv7`, `x86`, `x86_64`, `mips`, `mipsel`, `mips64`, `mips64el`, `powerpc`, `ppc64le`, `s390x`, `riscv64`, `loongarch64`
- [x] **macOS:** `x86_64`, `arm64` (universal2)

Notes:
- Linux static builds use `zig cc` and musl libc; OpenSSL for `-auth` variants is built from upstream source for each target.
- Target metadata is stored in `targets.json` and consumed by both `scripts/build-static.sh` and the GitHub Actions matrix generator.

## Experimental / expansion candidates

Candidates to investigate in a separate experimental workflow before promotion to stable:

- Missing endian/ABI variants of existing families: `armeb`, `ppc64` (big-endian), `riscv32`, MIPS n32 BE/LE.
- Additional embedded Linux ISA (best effort, toolchain dependent): ARC, SuperH, MicroBlaze, OpenRISC, m68k, C-SKY, Xtensa.
- Rare/specialized platforms (best effort): `aarch64_be`, `sparc`/`sparc64`, `alpha`, `hppa`/`parisc`, `x32`, `hexagon`, `powerpcspe`.
- Other operating systems are a separate track: Windows, BSD, Android, etc.
