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

Each release also includes `scan-report.json` and `scan-report.md` from
antivirus scanning (VirusTotal + MetaDefender Cloud) and `.sig`/`.cert` files
for Sigstore/cosign keyless signature verification. See `SECURITY.md` for
details.

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

## Supported Linux static targets

All Linux static builds are cross-compiled with the official [Zig](https://ziglang.org/)
toolchain (`zig cc`) and statically linked against musl libc.  `-auth` variants include
OpenSSL built from upstream source.  Every archive contains a `MANIFEST.json` with the
exact target triple, CPU/ABI metadata, compiler versions, and smoke-test status used
during the build.

| Target | ISA / CPU baseline | ABI | Endianness | FPU requirements | Auth | Testing | Limitations |
|---|---|---|---|---|---|---|---|
| `x86_64` | x86-64 | sysv | little | none | yes | native `--version` smoke test | none |
| `x86` | i686-class (x86 baseline) | sysv | little | x87 FPU or soft-float emulation | yes | runs natively on x86_64 host | intended for real 32-bit x86 systems |
| `aarch64` | ARMv8-A 64-bit | sysv | little | none | yes | QEMU user-mode `--version` smoke test | user-mode emulation only; not a real-device kernel/performance test |
| `arm` | ARMv5 / ARMv4T-compatible | EABI soft-float | little | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `armhf` | ARMv6 hard-float | EABI hard-float (VFP) | little | VFP | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `armv7` | ARMv7 hard-float | EABI hard-float (VFPv3) | little | VFPv3 | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `mips` | MIPS32 | o32 soft-float (musleabi) | big | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `mipsel` | MIPS32 | o32 soft-float (musleabi) | little | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `mips64` | MIPS64 | n64 soft-float (muslabi64) | big | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `mips64el` | MIPS64 | n64 soft-float (muslabi64) | little | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `powerpc` | 32-bit PowerPC | sysv soft-float (musleabi) | big | none (soft-float) | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `ppc64le` | PowerPC64 little-endian | ELFv2 | little | none | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `s390x` | IBM z/Architecture | sysv | big | none | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `riscv64` | RV64GC (RISC-V 64-bit) | lp64 | little | none | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `loongarch64` | LoongArch64 | sysv | little | none | yes | QEMU user-mode `--version` smoke test | user-mode emulation only |

### Experimental Linux static targets

The following targets are built only by the manually triggered
`experimental-builds.yml` workflow. They are not published as release assets
until they are promoted to stable.

| Target | Status | Auth | ISA / CPU baseline | ABI | Endianness | Testing | Known issues |
|---|---|---|---|---|---|---|---|
| `ppc64` | experimental | yes | 64-bit PowerPC | ELFv1 | big | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `riscv32` | experimental | yes | RISC-V 32-bit | ilp32 | little | QEMU user-mode `--version` smoke test | user-mode emulation only |
| `armeb` | experimental | no | ARM 32-bit big-endian | EABI soft-float | big | QEMU user-mode `--version` smoke test | no OpenSSL Configure target; plain-only |
| `mipsn32` | experimental | no | MIPS64 n32 ABI | n32 soft-float | big | QEMU user-mode `--version` smoke test | no OpenSSL n32 ABI target; plain-only |
| `mipsn32el` | experimental | no | MIPS64 n32 ABI | n32 soft-float | little | QEMU user-mode `--version` smoke test | no OpenSSL n32 ABI target; plain-only |
| `aarch64_be` | experimental | no | ARM64 big-endian | sysv | big | QEMU user-mode `--version` smoke test | no OpenSSL Configure target; plain-only |
| `hexagon` | experimental | no | Qualcomm Hexagon | sysv | little | QEMU user-mode `--version` smoke test | no OpenSSL Configure target; plain-only |

Promotion to stable requires passing builds for at least two consecutive
upstream releases, successful ELF verification, and documented QEMU smoke tests
for all built variants.

### Other variants

| Platform | Variant | libc / format | Best for | Notes |
|---|---|---|---|---|
| Linux x86_64 | dynamic | glibc 2.28 | CentOS Stream 8 / RHEL 8 / AlmaLinux 8 targets | Smaller, but needs compatible glibc |
| Linux x86_64 | dynamic-auth | glibc 2.28 + OpenSSL | glibc targets + RSA auth | Static OpenSSL; still needs compatible glibc |
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
