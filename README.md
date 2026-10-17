# iperf3-builds

[![Latest Release](https://img.shields.io/github/v/release/rusnino/iperf3-builds?sort=semver)](https://github.com/rusnino/iperf3-builds/releases/latest)
[![Build and Release](https://img.shields.io/github/actions/workflow/status/rusnino/iperf3-builds/build-release.yml?logo=github)](https://github.com/rusnino/iperf3-builds/actions/workflows/build-release.yml)

Automated builds of [esnet/iperf](https://github.com/esnet/iperf) for Linux
(x86_64, x86, ARM64, ARMv5/ARMv6/ARMv7, MIPS, PowerPC, s390x, RISC-V 64,
LoongArch 64) and macOS (Intel + Apple Silicon universal2).

This repository watches the upstream iperf3 project for new releases and
automatically compiles ready-to-use binaries. You do not need to install
build tools on your target system — just download a release archive and run
`iperf3`.

## Downloads

Pre-built binaries are published on the
[GitHub Releases](https://github.com/rusnino/iperf3-builds/releases) page.

Each upstream release produces the following assets:

- **Linux static builds** — statically linked with
  [musl](https://musl.libc.org/) and cross-compiled for many architectures.
  Each architecture has a plain archive and an `-auth` archive with
  statically-linked OpenSSL for RSA authentication
  (`--rsa-public-key-path`, `--rsa-private-key-path`, `--authorized-users-path`).

  Available architectures (`<arch>`):
  `x86_64`, `x86`, `aarch64`, `arm`, `armhf`, `armv7`, `mips`, `mipsel`,
  `mips64`, `mips64el`, `powerpc`, `ppc64le`, `s390x`, `riscv64`,
  `loongarch64`.

  Archive name pattern:
  `iperf3-<version>-linux-<arch>-static[-auth].tar.gz`

- **`iperf3-<version>-linux-x86_64-dynamic.tar.gz`** — dynamically linked with
  glibc, built on an AlmaLinux 8 / CentOS Stream 8 compatible environment. Use
  this if you prefer a glibc build and your target has glibc 2.28 or newer.
- **`iperf3-<version>-linux-x86_64-dynamic-auth.tar.gz`** — same as above, but
  with statically-linked OpenSSL for RSA authentication.
- **`iperf3-<version>-macos-universal2.tar.gz`** — universal2 binary that runs
  natively on both Intel and Apple Silicon Macs. Requires macOS 11.0 (Big Sur)
  or newer.
- **`iperf3-<version>-macos-universal2-auth.tar.gz`** — same as above, with
  statically-linked OpenSSL for RSA authentication.

A `SHA256SUMS` file is included with every release so you can verify the
archives.

> **Note:** Assets without `-auth` do not include OpenSSL, so iperf3's RSA
> authentication feature is not available. Use the `-auth` archives when you
> need authentication.

> **macOS quarantine:** If you download the macOS archive through a web
> browser, macOS may mark `iperf3` with a quarantine flag and show a
> “developer cannot be verified” warning when you first run it from Terminal.
> Remove the flag with `xattr -d com.apple.quarantine iperf3`, or allow it in
> System Settings → Privacy & Security.

## Quick start

```bash
VERSION=3.22
wget https://github.com/rusnino/iperf3-builds/releases/download/${VERSION}/iperf3-${VERSION}-linux-x86_64-static.tar.gz
tar -xzf iperf3-${VERSION}-linux-x86_64-static.tar.gz
./iperf3-${VERSION}-linux-x86_64-static/iperf3 --version
```

## Build variants

| Platform | Variant | libc / format | Best for | Notes |
|---|---|---|---|---|
| Linux x86_64 | static | musl | Maximum portability | No runtime dependencies |
| Linux x86_64 | static-auth | musl + OpenSSL | Maximum portability + RSA auth | No runtime dependencies |
| Linux x86_64 | dynamic | glibc 2.28 | CentOS Stream 8 / RHEL 8 / AlmaLinux 8 targets | Smaller, but needs compatible glibc |
| Linux x86_64 | dynamic-auth | glibc 2.28 + OpenSSL | glibc targets + RSA auth | Static OpenSSL; still needs compatible glibc |
| Linux aarch64 | static | musl | ARM64 servers and SBCs | Cross-compiled, smoke-tested with QEMU |
| Linux aarch64 | static-auth | musl + OpenSSL | ARM64 servers and SBCs + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux x86 | static | musl | 32-bit x86 systems / containers | Cross-compiled from x86_64; runs natively on x86_64 |
| Linux x86 | static-auth | musl + OpenSSL | 32-bit x86 + RSA auth | Cross-compiled from x86_64; runs natively on x86_64 |
| Linux aarch64 | static | musl | ARM64 servers and SBCs | Cross-compiled, smoke-tested with QEMU |
| Linux aarch64 | static-auth | musl + OpenSSL | ARM64 servers and SBCs + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux arm | static | musl | ARMv5 soft-float boards | Cross-compiled, smoke-tested with QEMU |
| Linux arm | static-auth | musl + OpenSSL | ARMv5 soft-float boards + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux armhf | static | musl | ARMv6 hard-float boards | Cross-compiled, smoke-tested with QEMU |
| Linux armhf | static-auth | musl + OpenSSL | ARMv6 hard-float boards + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux armv7 | static | musl | ARMv7 hard-float boards | Cross-compiled, smoke-tested with QEMU |
| Linux armv7 | static-auth | musl + OpenSSL | ARMv7 hard-float boards + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux mips | static | musl | MIPS 32-bit big-endian | Cross-compiled, smoke-tested with QEMU |
| Linux mips | static-auth | musl + OpenSSL | MIPS 32-bit big-endian + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux mipsel | static | musl | MIPS 32-bit little-endian | Cross-compiled, smoke-tested with QEMU |
| Linux mipsel | static-auth | musl + OpenSSL | MIPS 32-bit little-endian + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux mips64 | static | musl | MIPS 64-bit big-endian | Cross-compiled, smoke-tested with QEMU |
| Linux mips64 | static-auth | musl + OpenSSL | MIPS 64-bit big-endian + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux mips64el | static | musl | MIPS 64-bit little-endian | Cross-compiled, smoke-tested with QEMU |
| Linux mips64el | static-auth | musl + OpenSSL | MIPS 64-bit little-endian + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux powerpc | static | musl | 32-bit PowerPC | Cross-compiled, smoke-tested with QEMU |
| Linux powerpc | static-auth | musl + OpenSSL | 32-bit PowerPC + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux ppc64le | static | musl | 64-bit little-endian PowerPC | Cross-compiled, smoke-tested with QEMU |
| Linux ppc64le | static-auth | musl + OpenSSL | 64-bit little-endian PowerPC + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux s390x | static | musl | IBM Z / s390x | Cross-compiled, smoke-tested with QEMU |
| Linux s390x | static-auth | musl + OpenSSL | IBM Z / s390x + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux riscv64 | static | musl | RISC-V 64-bit | Cross-compiled, smoke-tested with QEMU |
| Linux riscv64 | static-auth | musl + OpenSSL | RISC-V 64-bit + RSA auth | Cross-compiled, smoke-tested with QEMU |
| Linux loongarch64 | static | musl | LoongArch 64-bit | Cross-compiled, smoke-tested with QEMU |
| Linux loongarch64 | static-auth | musl + OpenSSL | LoongArch 64-bit + RSA auth | Cross-compiled, smoke-tested with QEMU |
| macOS | universal2 | system libs | Intel and Apple Silicon Macs | Requires macOS 11.0+; ad-hoc signed, not notarized |
| macOS | universal2-auth | system libs + OpenSSL | Intel and Apple Silicon Macs + RSA auth | Requires macOS 11.0+; ad-hoc signed, not notarized |

## Automation

A GitHub Actions workflow runs daily at 04:00 UTC, checks the last 10 upstream
releases, and builds any missing ones. Maintainers can also trigger a build
manually from the **Actions → Build and Release → Run workflow** tab.

## License

The build scripts in this repository are released under the same license as
iperf3 itself (BSD 3-clause). The upstream license is included in each release
archive.
