# Cross-platform iperf3 builds — design

## Intent

Extend `rusnino/iperf3-builds` so it produces ready-to-run iperf3 binaries for
the most common non-Windows platforms people actually use. Users should be able
to download an archive, unpack it, and run `./iperf3` in a terminal without
installing build tools or runtime libraries.

## Why now

The repository already successfully builds Linux x86_64 static (musl) and
dynamic (glibc 2.28) binaries. Users with ARM-based single-board computers,
Apple Silicon Macs, and older Intel Macs also need binaries. Adding these
platforms increases the utility of the automated release pipeline without
requiring paid infrastructure.

## Goals

- Produce the following assets for every upstream iperf3 release:
  - Linux x86_64 static (musl) — already exists.
  - Linux x86_64 dynamic (glibc 2.28) — already exists.
  - Linux ARM64 static (musl).
  - Linux ARM32 static (musl).
  - macOS universal2 binary (x86_64 + arm64 in one file).
- Publish all assets on the same GitHub Release with upstream release notes
  and a single `SHA256SUMS` file.
- Keep the release pipeline fully on free GitHub Actions runners.
- Keep the existing Linux x86_64 static/dynamic behavior unchanged.

## Non-goals

- No Windows builds.
- No FreeBSD / OpenBSD / NetBSD / Solaris / illumos builds in this phase.
- No dynamic glibc builds for ARM64 / ARM32 in this phase.
- No 32-bit x86 (i386/i686) Linux build in this phase.
- No Homebrew tap, .pkg installer, or .app bundle for macOS.
- No code signing or Apple notarization (no Apple Developer ID).

## Anti-goals

- Do not require self-hosted runners or paid runners.
- Do not turn one release into a wall of confusing artifacts.
- Do not break the existing x86_64 Linux pipeline.

## Constraints

- GitHub Actions free runners only.
- Repository is public, so macOS minutes are free but slower than Linux.
- No Apple Developer account is available.
- iperf3 is a command-line tool; users run it from a terminal.

## Supported platforms (first wave)

| OS | Architecture | Variant | Runner / toolchain | Asset example |
|---|---|---|---|---|
| Linux | x86_64 | static | `ubuntu-latest`, host `musl-gcc` | `iperf3-3.22-linux-x86_64-static.tar.gz` |
| Linux | x86_64 | dynamic | `ubuntu-latest` + `almalinux:8` container | `iperf3-3.22-linux-x86_64-dynamic.tar.gz` |
| Linux | aarch64 | static | `ubuntu-latest` + `musl.cc` cross toolchain | `iperf3-3.22-linux-aarch64-static.tar.gz` |
| Linux | armv7 | static | `ubuntu-latest` + `musl.cc` cross toolchain | `iperf3-3.22-linux-armv7-static.tar.gz` |
| macOS | universal2 | release tarball build | `macos-26-intel` + `macos-26`, merged with `lipo` | `iperf3-3.22-macos-universal2.tar.gz` |

Architecture names in filenames follow common conventions: `x86_64`, `aarch64`,
`armv7`, `universal2`.

## Build strategy

### Linux static cross builds

Use the prebuilt musl-based cross toolchains from
[musl.cc](https://musl.cc):

- `aarch64-linux-musl-cross.tgz`
- `armv7l-linux-musleabihf-cross.tgz` or `arm-linux-musleabihf-cross.tgz`
- `i686-linux-musl-cross.tgz` (kept in backlog for future i386 support)

Each toolchain is downloaded once per job, extracted to `/opt/cross`, and
used as `CC=/opt/cross/bin/aarch64-linux-musl-gcc` (or equivalent). The build
script runs `./configure` with `CFLAGS="-static"` and `--disable-shared`, then
verifies the resulting ELF has the expected architecture and is statically
linked.

Because the iperf3 release tarball already contains a generated `configure`, no
host autotools are needed for the common case. If a release lacks a tarball,
the existing git-clone + `autoreconf -fi` fallback runs on the Ubuntu host
(which has autoconf 2.72).

### Smoke tests

- Linux x86_64 static/dynamic: run `./iperf3 --version` in the build environment.
- Linux ARM64 / ARM32 cross builds: install `qemu-user-static` and run
  `./iperf3 --version` under QEMU. Also verify architecture and static
  linkage with `file` and `readelf -h`.
- macOS x86_64 build: run `./iperf3 --version` on `macos-26-intel`.
- macOS arm64 build: run `./iperf3 --version` on `macos-26`.
- macOS universal2 binary: run `lipo -info`, `file`, and `./iperf3 --version`
  on `macos-26` (arm64 slice runs natively).

### macOS universal2 build

1. Fetch the iperf3 release tarball. If it is missing, fall back to
   `git clone` of the upstream tag and install autotools via Homebrew:
   `brew install autoconf automake libtool`, then `autoreconf -fi`.
2. Build an x86_64 binary on `macos-26-intel`.
3. Build an arm64 binary on `macos-26`.
4. Upload both single-arch binaries as artifacts.
5. Run a merge job on `macos-26` that downloads both artifacts and runs
   `lipo -create iperf3-x86_64 iperf3-arm64 -output iperf3` to produce a
   `universal2` binary.
6. Package the universal binary with `README.md` and `LICENSE` into
   `iperf3-{VERSION}-macos-universal2.tar.gz`.

The macOS build uses the system compiler and links dynamically against macOS
system libraries. It is not a fully static musl build (musl does not target
macOS). To improve compatibility, set `MACOSX_DEPLOYMENT_TARGET=11.0` during
configure. The final binary is ad-hoc signed with `codesign -s - iperf3`; this
does not satisfy Gatekeeper for browser-downloaded files, but it satisfies
some local integrity checks and matches what many unsigned CLI tools do.

### Artifact handling

Each build job uploads exactly one archive. The release job downloads all
artifacts, computes `sha256sum` for every archive, writes `SHA256SUMS`, and
creates the GitHub Release with all files. The release job continues to copy
the upstream `prerelease` flag and only marks the release as `Latest` when the
version matches the current upstream stable latest.

## Failure handling

The `release` job `needs` every build job. If any build job fails, no release
is created. This preserves the existing rule: do not publish partial artifacts.

## Backlog (future phases)

- Dynamic glibc builds for ARM64 and ARM32 (requires CentOS/AlmaLinux ARM
  container or cross toolchain).
- 32-bit x86 (i386/i686) Linux static build.
- FreeBSD / OpenBSD / NetBSD / Solaris / illumos builds.
- Homebrew tap.
- Apple Developer ID signing and notarization.
- Sigstore/cosign signing of release archives.
- Docker / OCI image.
- Artifact retention reduction.
- Localized release notes.
- Auto-deprecation of stale pre-releases.

## Resolved decisions

- macOS deployment target: `11.0` (Big Sur and newer).
- macOS tarball fallback: same as Linux (`git clone` + autotools via Homebrew).
- Smoke testing: native `./iperf3 --version` where possible; QEMU user-mode for
  cross-compiled Linux ARM binaries.
- No Apple signing/notarization; ad-hoc `codesign -s -` only.

## Open questions / builder decisions

- ARM32 target triple from musl.cc: `arm-linux-musleabihf` vs `armv7l-linux-musleabihf`.
  Both cover modern 32-bit ARM boards; the final choice will be made during
  implementation based on which tarball is available and stable.
